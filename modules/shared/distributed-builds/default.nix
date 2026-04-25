# Distributed Nix builds across the Thunderbolt cluster.
#
# Each cluster node acts as a remote builder for the others, offloading
# long builds (node_modules, Python venvs, etc.) across all machines.
#
# Each machine is listed twice:
#   1. .tb hostname (speedFactor=2) — Thunderbolt Bridge, preferred
#   2. .local hostname (speedFactor=1) — mDNS/WiFi, fallback
#
# Nix will use whichever builders are reachable. If TB is disconnected
# on a node, .local picks up the slack automatically.
#
# Requirements on each builder node:
#   - The initiating machine's SSH public key in ~/.ssh/authorized_keys
#   - `nix-daemon` trusted-users includes casazza (set via trusted-users below)
#   - The builder must have the same Nix version (Determinate Nix on all nodes)
#
# Per-host opt-out:
#   When you're on a network where none of the cluster nodes resolve (e.g.
#   off-VPN, traveling, or the other Macs are asleep), every `nix develop`
#   stalls for ~5s/builder on mDNS lookups + SSH ConnectTimeout before
#   falling back to local/substitute builds. Set
#       casazza.distributedBuilds.enable = false;
#   in that host's `systems/aarch64-darwin/<HOST>/default.nix` to skip the
#   builders entirely on that machine. Flip back when you're home.
{
  lib,
  config,
  isDeterminate,
  user,
  exoThunderboltHostname ? null,
  ...
}:
let
  cfg = config.casazza.distributedBuilds;

  sshKey = "/Users/casazza/.ssh/id_ed25519";

  # SSH user per system — darwin and NixOS hosts both use casazza.
  sshUserForSystem = system: if system == "x86_64-linux" then "casazza" else "casazza";

  # Define cluster nodes. Each gets two builder entries: TB (preferred) + .local (fallback).
  clusterNodes = [
    {
      hostname = "GN9CFLM92K-MBP";
      system = "aarch64-darwin";
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    }
    {
      hostname = "CK2Q9LN7PM-MBA";
      system = "aarch64-darwin";
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostname = "GJHC5VVN49-MBP";
      system = "aarch64-darwin";
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostname = "L75T4YHXV7-MBA";
      system = "aarch64-darwin";
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostname = "desk-nxst-001";
      system = "x86_64-linux";
      maxJobs = 4;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    }
  ];

  # Expand each node into builder entries.
  # TB entries are commented out until Thunderbolt cables are connected.
  allBuilders = lib.concatMap (node: [
    # {
    #   hostName = "${node.hostname}.tb";
    #   system = node.system;
    #   sshUser = sshUserForSystem node.system;
    #   inherit sshKey;
    #   maxJobs = node.maxJobs;
    #   speedFactor = 2;
    #   supportedFeatures = node.supportedFeatures;
    # }
    {
      hostName = "${node.hostname}.local";
      system = node.system;
      sshUser = sshUserForSystem node.system;
      inherit sshKey;
      maxJobs = node.maxJobs;
      speedFactor = 1;
      supportedFeatures = node.supportedFeatures;
    }
  ]) clusterNodes;

  # Exclude both .tb and .local entries for this machine to avoid SSH-to-localhost.
  builders = builtins.filter (
    b:
    exoThunderboltHostname == null
    || (b.hostName != "${exoThunderboltHostname}.tb" && b.hostName != "${exoThunderboltHostname}.local")
  ) allBuilders;

  # Format a builder attrset as a nix.conf builders line:
  # ssh-ng://... format: user@host system key maxJobs speed features - - ssh-options
  # ConnectTimeout=5 + BatchMode=yes: fail fast if builder is offline or needs a password.
  builderLine =
    b:
    "ssh-ng://${b.sshUser}@${b.hostName} ${b.system} ${b.sshKey} ${toString b.maxJobs} ${toString b.speedFactor} ${lib.concatStringsSep "," b.supportedFeatures} - - ConnectTimeout=5,BatchMode=yes";

  buildersConf = lib.concatMapStringsSep " ; " builderLine builders;
in
{
  options.casazza.distributedBuilds = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable distributed Nix builds across the Thunderbolt
        cluster. Set to false on machines that are commonly off-network
        from the other cluster nodes — otherwise every `nix develop` /
        `direnv allow` stalls on mDNS lookups for unreachable builders.
      '';
    };
  };

  config = lib.mkMerge [
    # Determinate Nix: append builder config to nix.custom.conf.
    # environment.etc.<name>.text uses lib.types.lines which concatenates
    # multiple module definitions automatically — no conflict with cachix module.
    (lib.mkIf (isDeterminate && cfg.enable) {
      environment.etc."nix/nix.custom.conf".text = ''
        builders = ${buildersConf}
        builders-use-substitutes = true
        fallback = true
        max-jobs = auto
        connect-timeout = 5
        trusted-users = root ${user.name}
      '';
    })

    # Determinate Nix, builders disabled: still apply the non-builder
    # settings so trusted-users / fallback / max-jobs stay correct.
    (lib.mkIf (isDeterminate && !cfg.enable) {
      environment.etc."nix/nix.custom.conf".text = ''
        builders =
        builders-use-substitutes = true
        fallback = true
        max-jobs = auto
        connect-timeout = 5
        trusted-users = root ${user.name}
      '';
    })

    # Standard Nix (non-Determinate Linux hosts)
    (lib.mkIf (!isDeterminate && cfg.enable) {
      nix.distributedBuilds = true;
      nix.buildMachines = builders;
      nix.settings = {
        builders-use-substitutes = true;
        fallback = true;
        max-jobs = "auto";
        trusted-users = [
          "root"
          user.name
        ];
      };
    })

    (lib.mkIf (!isDeterminate && !cfg.enable) {
      nix.distributedBuilds = false;
      nix.settings = {
        fallback = true;
        max-jobs = "auto";
        trusted-users = [
          "root"
          user.name
        ];
      };
    })
  ];
}
