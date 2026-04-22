# Arize Phoenix as a declarative systemd service.
#
# Phoenix (https://docs.arize.com/phoenix) is an OTLP trace sink + live
# UI for LLM app observability. luna uses it as the trace store for
# everything in the swarm: LiteLLM, LangGraph Server (swarm + ingest),
# and any manual graph runs under `nix develop`.
#
# Before this module existed, Phoenix ran out of
# `projects/swarm/scripts/start-phoenix.sh` inside an interactive
# `nix develop`. That left Phoenix as the one swarm component not
# declaratively managed — the sibling modules
# (`local.litellm`, `local.langgraphServer`) got promoted earlier.
# This module closes that gap.
#
# Packaging approach (mirrors `modules/nixos/litellm/default.nix`):
#   * `arize-phoenix` ships on PyPI. We install it into a uv-managed
#     venv at first service start, pinned by `cfg.phoenixVersion`. The
#     venv is version-stamped and auto-recreated on version bumps.
#   * Trace DB + artifacts land under `cfg.workingDir` (default
#     `/var/lib/phoenix`). Persists across reboots; wipe the dir to
#     reset trace history.
#
# Ports:
#   * cfg.port (default 6006) — Phoenix HTTP + UI, also serves OTLP/HTTP
#     at /v1/traces. This is what LiteLLM and LangGraph Server point
#     `OTEL_EXPORTER_OTLP_ENDPOINT` at by default.
#   * cfg.grpcPort (default 4319) — OTLP gRPC. Non-standard (4317 is
#     the OTLP/gRPC default) to avoid colliding with luna's
#     `otelcol-contrib` collector already bound on 4317.
#
# Usage:
#   local.phoenix = {
#     enable = true;
#     openFirewall = true;
#   };
#
# Verify (after switch):
#   curl http://luna.local:6006/healthz        # liveness
#   curl http://luna.local:6006/v1/traces -I   # OTLP/HTTP surface
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.phoenix;

  # Bootstrap a uv-managed venv at first start, pip-install pinned
  # arize-phoenix, stamp the version, then exec `phoenix serve`.
  # Idempotent across restarts; version drift triggers a full venv
  # rebuild (same pattern as litellm / vllm / mcpo).
  startScript = pkgs.writeShellScript "phoenix-start" ''
    set -eu

    VENV="${cfg.venvDir}"
    PHOENIX_VERSION="${cfg.phoenixVersion}"
    VERSION_STAMP="$VENV/.phoenix-version"

    if [ -x "$VENV/bin/python" ] && [ -f "$VERSION_STAMP" ]; then
      installed_version="$(cat "$VERSION_STAMP")"
      if [ "$installed_version" != "$PHOENIX_VERSION" ]; then
        echo "phoenix: version changed ($installed_version -> $PHOENIX_VERSION), recreating venv"
        rm -rf "$VENV"
      fi
    fi

    if [ ! -x "$VENV/bin/python" ]; then
      echo "phoenix: bootstrapping venv at $VENV"
      ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
    fi

    # `setuptools` is kept in the install list for the same reason as
    # litellm / vllm: a few transitive deps lazy-import `setuptools`
    # at runtime, and phoenix doesn't pull it in as a hard dep.
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
      --quiet \
      "arize-phoenix==$PHOENIX_VERSION" \
      "setuptools"

    echo "$PHOENIX_VERSION" > "$VERSION_STAMP"

    exec "$VENV/bin/phoenix" serve
  '';
in
{
  options.local.phoenix = {
    enable = mkEnableOption "Arize Phoenix (OTLP trace sink + UI)";

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address for the HTTP + OTLP listeners. Default `0.0.0.0`
        so LAN workers (darwin fleet, exo nodes) can post spans here.
        Flip to `127.0.0.1` for loopback-only.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 6006;
      description = ''
        HTTP port. Hosts the UI and the OTLP/HTTP receiver at
        `/v1/traces` — this is what `OTEL_EXPORTER_OTLP_ENDPOINT`
        typically points at across the swarm.
      '';
    };

    grpcPort = mkOption {
      type = types.port;
      default = 4319;
      description = ''
        OTLP/gRPC port. Deliberately non-standard — the OTLP/gRPC
        default is 4317, but luna's `otelcol-contrib` is already bound
        there. 4318 is the OTLP/HTTP default (also in wide use), so we
        pick 4319 to stay clear of both.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` + `cfg.grpcPort` on the host firewall. Off by
        default. Phoenix has no authentication, so only flip this on
        for LAN-trusted hosts (same posture as `local.langgraphServer`).
      '';
    };

    workingDir = mkOption {
      type = types.path;
      default = "/var/lib/phoenix";
      description = ''
        Phoenix state directory — trace DB, vectors, artifacts.
        Exported as `PHOENIX_WORKING_DIR` at service start. Persistent
        across reboots; wipe it to reset trace history.
      '';
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables exported to the Phoenix process.
        Useful for toggling auth, DB backend, etc. — see
        https://docs.arize.com/phoenix/self-hosting/configuration for
        the full list of `PHOENIX_*` variables.
      '';
    };

    phoenixVersion = mkOption {
      type = types.str;
      default = "14.10.0";
      description = ''
        PyPI version of `arize-phoenix` to install into the venv.
        Matches what swarm/uv.lock resolves to. History:
        https://pypi.org/project/arize-phoenix/#history

        Changing this triggers a venv recreation on next service start
        (the wrapper stamps `.phoenix-version` and recreates when it
        differs).
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = ''
        Python interpreter the venv is built around. Phoenix wheels
        target Python 3.9–3.12 as of 14.x.
      '';
    };

    uv = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "uv binary used to bootstrap and update the venv.";
    };

    venvDir = mkOption {
      type = types.path;
      default = "/var/lib/phoenix/venv";
      description = ''
        Persistent uv venv location. Survives nixos-rebuilds. Wipe it
        if the Python / Phoenix version combo drifts incompatibly:
            sudo rm -rf /var/lib/phoenix/venv
        and the next service start will rebuild.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "phoenix";
      description = "System user that runs the Phoenix server.";
    };

    group = mkOption {
      type = types.str;
      default = "phoenix";
      description = "System group for the Phoenix server.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.workingDir;
      createHome = true;
      description = "Arize Phoenix";
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.workingDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${builtins.dirOf cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      cfg.port
      cfg.grpcPort
    ];

    systemd.services.phoenix = {
      description = "Arize Phoenix (OTLP trace sink + UI)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # uv's venv bootstrap shells out to a C compiler when a
      # transitive dep has to build from source (some gRPC / protobuf
      # paths). systemd services start with a near-empty PATH; without
      # this the first install can die with `cc: command not found`.
      path = [
        pkgs.gcc
        pkgs.binutils
        pkgs.git
      ];

      environment = {
        HOME = cfg.workingDir;
        PHOENIX_WORKING_DIR = cfg.workingDir;
        PHOENIX_HOST = cfg.host;
        PHOENIX_PORT = toString cfg.port;
        PHOENIX_GRPC_PORT = toString cfg.grpcPort;
        # Pip-wheel deps (grpcio, tiktoken, etc.) dlopen libstdc++.so.6
        # + libz.so.1 at import time assuming an FHS layout. NixOS has
        # no global library path, so surface both here to avoid
        # ImportError at service start.
        LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ];
      }
      // cfg.extraEnv;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workingDir;

        ExecStart = startScript;

        # Cold starts pull the arize-phoenix wheel (~150 MiB of deps);
        # give enough headroom for slow network.
        TimeoutStartSec = "15min";

        Restart = "on-failure";
        RestartSec = "15s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = "10min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [
          cfg.workingDir
          cfg.venvDir
          (builtins.dirOf cfg.venvDir)
        ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;

        LimitNOFILE = 65536;
      };
    };
  };
}
