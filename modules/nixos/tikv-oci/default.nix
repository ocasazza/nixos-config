# TiKV as an OCI container (podman), parallel-track.
#
# Why OCI-containers (podman) vs. LXD vs. nixpkgs from-source:
#   * nixpkgs from-source: the seaweedfs flake exposes `pkgs.tikv` /
#     `pkgs.tikv-pd`, but TiKV 8.5.0's vendored C++ tree (grpcio-sys
#     → rocksdb-sys → abseil lts_20211102) does not build under the
#     current nixpkgs stdenv (gcc 15, cmake 4.1). Each "fix" uncovers
#     another vendored-dep breakage — CMake 4 minimum-version → gcc 15
#     deprecated headers → abseil symbol-visibility regressions. Not a
#     dep tree worth patching downstream.
#   * LXD: Canonical's system-container platform. On NixOS 25.11,
#     `virtualisation.lxd.enable = true` brings the daemon up, but
#     LXD's OCI-image support (`lxc init docker:pingcap/tikv:v8.5.0`)
#     requires distrobuilder-style image conversion, a storage pool
#     (zfs/btrfs/dir), and a network bridge — a lot of ceremony for
#     what is fundamentally a single long-running process per image.
#   * podman via `virtualisation.oci-containers`: ONE option flip, each
#     container gets a proper systemd unit under `podman-<name>.service`
#     with declarative ExecStart, `dependsOn` → systemd `Requires=`/
#     `After=`, bind-mounts via `volumes`, ports via `ports`. Podman is
#     already enabled on luna (`virtualisation.podman.enable = true`)
#     and the daemonless model plays well with systemd's sandboxing.
#
# Upshot: `virtualisation.oci-containers.backend = "podman"` is the path
# with less ceremony here. LXD buys us nothing for an app-container
# workload; reserve LXD for when a full system-container OS image is
# actually what we want.
#
# Container wiring:
#   * `tikv-pd` — Placement Driver (PD). Single-node quorum (cluster
#     has one member, initial-cluster = "pd1=http://<advertise>:2380").
#     Listens on 2379 (client) / 2380 (peer). TiKV 8.5 still requires
#     PD; there is no "embedded-PD" or "no-PD" mode.
#   * `tikv-server` — KV store. Listens on 20160 (gRPC) / 20180
#     (status/metrics). Connects to PD at 2379. `dependsOn = ["tikv-pd"]`
#     makes the rendered systemd unit carry `Requires=podman-tikv-pd.service`
#     + `After=podman-tikv-pd.service`, so start order is correct and a PD
#     restart propagates to TiKV.
#
# Networking: host networking (`--network=host`) for both containers.
# TiKV's gRPC/raft protocol and PD's raft-based peer protocol work
# cleanly over loopback with host networking — no bridge NAT to fight,
# and the `advertise-addr` values can stay `127.0.0.1` so any in-host
# client (JuiceFS, debug tools) connects on loopback the same way it
# would against a native install.
#
# Storage: persistent bind mounts at `${cfg.dataDir}/pd` and
# `${cfg.dataDir}/tikv`. Survive rebuilds and container recreations.
# RocksDB corruption on crash is handled by TiKV's own WAL; nothing
# else in Nix-land can substitute for that.
#
# Auth posture: TiKV's gRPC has NO auth by default. With host networking
# on luna, these ports are only bound to `127.0.0.1` (see `ports =
# ["127.0.0.1:…"]` below). This matches the "Redis everywhere on
# loopback-only" threat model used elsewhere in this repo. Only set
# `openFirewall = true` if you explicitly want LAN-reachable TiKV —
# in which case you'd also want TLS + user authentication, neither of
# which are configured here. Parallel-track: do not expose externally.
#
# Why NOT wire SeaweedFS at this stage:
#   The primary SeaweedFS metadata store flip is happening on
#   `casazza/seaweedfs-redis-backend`. This module is a parallel-track
#   install — containers up, ports reachable, available for eval, but
#   `services.seaweedfs.filer.store` is intentionally untouched. To flip
#   SeaweedFS to this TiKV later, add (in the luna host config):
#     services.seaweedfs.filer.store = "tikv";
#     services.seaweedfs.filer.tikvPdAddrs = [ "127.0.0.1:2379" ];
#   (names depend on the seaweedfs flake's module options; see its
#   `modules/nixos/seaweedfs/` for the exact attr names.)
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.tikvOci;

  # Bind-address prefix for the container ports. Loopback-only when the
  # firewall is closed (default); `0.0.0.0` otherwise so LAN peers can
  # reach it. Podman's --publish accepts `<host-ip>:<host-port>:<ctr-port>`.
  bindHost = if cfg.openFirewall then "0.0.0.0" else "127.0.0.1";

  # Advertise addresses inside the container. Because we use host
  # networking below, `127.0.0.1` is the same loopback the containers
  # see as the host sees — no bridge, no NAT, no rewriting. For
  # LAN-exposed mode, advertise the host's LAN name so peers dial us
  # correctly. `luna.local` is provided by the avahi config on this
  # host; fine to hardcode here because this module is luna-specific
  # parallel-track eval infra.
  pdAdvertiseHost = if cfg.openFirewall then "luna.local" else "127.0.0.1";
in
{
  options.local.tikvOci = {
    enable = mkEnableOption ''
      TiKV running as an OCI container (parallel-track, NOT the active
      SeaweedFS filer backend). Pulls `pingcap/pd` and `pingcap/tikv`
      images from Docker Hub. Available for eval on loopback; flip
      `openFirewall` only if you want LAN-reachable TiKV (no TLS/auth
      configured — loopback-only is the intended posture)
    '';

    pdImage = mkOption {
      type = types.str;
      default = "docker.io/pingcap/pd:v8.5.0";
      description = ''
        Full OCI image reference for the Placement Driver. Podman
        resolves `docker.io/…` against Docker Hub by default; we fully-
        qualify the registry here to avoid any short-name resolution
        ambiguity (podman 4.x errors on unqualified short names unless
        `unqualified-search-registries` is set).
      '';
    };

    tikvImage = mkOption {
      type = types.str;
      default = "docker.io/pingcap/tikv:v8.5.0";
      description = "Full OCI image reference for the TiKV server.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/tikv-oci";
      description = ''
        Host directory that holds persistent container state. Two
        subdirs are bind-mounted into the containers:
          * `${cfg.dataDir}/pd`   → `/var/lib/pd`    (PD's raft log + store)
          * `${cfg.dataDir}/tikv` → `/var/lib/tikv`  (RocksDB data)
        Survives nixos-rebuilds, podman restarts, and image upgrades.
        Wipe to reset the cluster (destroys all KV data).
      '';
    };

    ports = {
      pdClient = mkOption {
        type = types.port;
        default = 2379;
        description = "PD client port (gRPC). TiKV + SDK clients dial this.";
      };
      pdPeer = mkOption {
        type = types.port;
        default = 2380;
        description = ''
          PD raft peer port. Irrelevant for a single-member cluster but
          PD still listens on it; published for future scale-out.
        '';
      };
      tikv = mkOption {
        type = types.port;
        default = 20160;
        description = "TiKV gRPC service port (read/write KV ops).";
      };
      tikvMetrics = mkOption {
        type = types.port;
        default = 20180;
        description = ''
          TiKV status/metrics port. Prometheus scrape target
          (`/metrics`) and debugging HTTP surface.
        '';
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open the four TiKV/PD ports on the host firewall AND bind the
        published ports on `0.0.0.0` instead of `127.0.0.1`. Off by
        default — TiKV ships no TLS or auth; loopback-only is the only
        safe posture for the parallel-track eval install.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Podman backend for the NixOS oci-containers abstraction. luna
    # already has `virtualisation.podman.enable = true`, so this just
    # selects which runtime the generated systemd units shell out to.
    # `mkDefault` so a host config can override (e.g. to "docker") without
    # this module's opinion fighting it.
    virtualisation.oci-containers.backend = mkDefault "podman";

    # Create the bind-mount targets with tight perms. Podman runs these
    # containers as root by default (TiKV + PD inside the image run as
    # uid 0); the bind-mount needs to exist before unit-start so podman
    # doesn't auto-create it with the wrong owner/mode.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}        0750 root root -"
      "d ${cfg.dataDir}/pd     0750 root root -"
      "d ${cfg.dataDir}/tikv   0750 root root -"
    ];

    # Firewall opens only when explicitly requested. Loopback ports
    # aren't firewalled to begin with (iptables INPUT chain ignores
    # lo traffic on default NixOS firewall), so the list is meaningful
    # only in `openFirewall = true` mode.
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      cfg.ports.pdClient
      cfg.ports.pdPeer
      cfg.ports.tikv
      cfg.ports.tikvMetrics
    ];

    virtualisation.oci-containers.containers = {
      # ── PD (Placement Driver) ─────────────────────────────────────
      tikv-pd = {
        image = cfg.pdImage;

        # Host networking: the simplest path. `--network=host` makes the
        # container share the host's network namespace, so PD's `--client-urls`
        # / `--peer-urls` binding to 0.0.0.0:2379 / 0.0.0.0:2380 is actually
        # binding on the host (no podman bridge, no NAT). This is also what
        # pingcap's own "single-node TiKV with docker" examples recommend.
        extraOptions = [ "--network=host" ];

        # We still set `ports` here for documentation + for environments
        # where host-networking is swapped to bridged (future-proofing).
        # With --network=host, the oci-containers module ignores these;
        # they become an annotation.
        ports = [
          "${bindHost}:${toString cfg.ports.pdClient}:${toString cfg.ports.pdClient}"
          "${bindHost}:${toString cfg.ports.pdPeer}:${toString cfg.ports.pdPeer}"
        ];

        volumes = [
          "${cfg.dataDir}/pd:/var/lib/pd"
        ];

        # PD's CLI. Single-member cluster — `initial-cluster` lists
        # one member ("pd1" = this node). Upstream's entrypoint is
        # `/pd-server`, so `cmd` supplies just the flags.
        cmd = [
          "--name=pd1"
          "--data-dir=/var/lib/pd"
          "--client-urls=http://0.0.0.0:${toString cfg.ports.pdClient}"
          "--peer-urls=http://0.0.0.0:${toString cfg.ports.pdPeer}"
          "--advertise-client-urls=http://${pdAdvertiseHost}:${toString cfg.ports.pdClient}"
          "--advertise-peer-urls=http://${pdAdvertiseHost}:${toString cfg.ports.pdPeer}"
          "--initial-cluster=pd1=http://${pdAdvertiseHost}:${toString cfg.ports.pdPeer}"
        ];
      };

      # ── TiKV server ──────────────────────────────────────────────
      tikv-server = {
        image = cfg.tikvImage;

        extraOptions = [ "--network=host" ];

        ports = [
          "${bindHost}:${toString cfg.ports.tikv}:${toString cfg.ports.tikv}"
          "${bindHost}:${toString cfg.ports.tikvMetrics}:${toString cfg.ports.tikvMetrics}"
        ];

        volumes = [
          "${cfg.dataDir}/tikv:/var/lib/tikv"
        ];

        # `dependsOn` is the oci-containers module's own ordering hint;
        # it renders to `Requires=podman-tikv-pd.service` +
        # `After=podman-tikv-pd.service` on the tikv-server unit. That
        # means a PD restart propagates (TiKV unit stops too) and boot
        # ordering is guaranteed without us hand-writing systemd deps.
        dependsOn = [ "tikv-pd" ];

        cmd = [
          "--pd-endpoints=${pdAdvertiseHost}:${toString cfg.ports.pdClient}"
          "--addr=0.0.0.0:${toString cfg.ports.tikv}"
          "--advertise-addr=${pdAdvertiseHost}:${toString cfg.ports.tikv}"
          "--status-addr=0.0.0.0:${toString cfg.ports.tikvMetrics}"
          "--advertise-status-addr=${pdAdvertiseHost}:${toString cfg.ports.tikvMetrics}"
          "--data-dir=/var/lib/tikv"
        ];
      };
    };
  };
}
