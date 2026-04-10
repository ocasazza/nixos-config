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
{
  lib,
  isDeterminate,
  user,
  exoThunderboltHostname ? null,
  ...
}:
let
  sshKey = "/Users/casazza/.ssh/id_ed25519";
  sshUser = "casazza";

  # Define cluster nodes. Each gets two builder entries: TB (preferred) + .local (fallback).
  clusterNodes = [
    {
      hostname = "GN9CFLM92K-MBP";
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
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostname = "GJHC5VVN49-MBP";
      maxJobs = 6;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    # L75T4YHXV7-MBA — not yet bootstrapped, re-enable when ready
    # {
    #   hostname = "L75T4YHXV7-MBA";
    #   maxJobs = 6;
    #   supportedFeatures = [
    #     "nixos-test"
    #     "benchmark"
    #     "big-parallel"
    #   ];
    # }
  ];

  # Expand each node into builder entries.
  # TB entries are commented out until Thunderbolt cables are connected.
  allBuilders = lib.concatMap (node: [
    # {
    #   hostName = "${node.hostname}.tb";
    #   system = "aarch64-darwin";
    #   inherit sshUser sshKey;
    #   maxJobs = node.maxJobs;
    #   speedFactor = 2;
    #   supportedFeatures = node.supportedFeatures;
    # }
    {
      hostName = "${node.hostname}.local";
      system = "aarch64-darwin";
      inherit sshUser sshKey;
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
  # ssh://user@host system key maxJobs speed features
  # ssh-ng://... format: user@host system key maxJobs speed features - - ssh-options
  # ConnectTimeout=5 prevents builds from hanging when a builder is offline.
  builderLine =
    b:
    "ssh-ng://${b.sshUser}@${b.hostName} ${b.system} ${b.sshKey} ${toString b.maxJobs} ${toString b.speedFactor} ${lib.concatStringsSep "," b.supportedFeatures} - - ConnectTimeout=5";

  buildersConf = lib.concatMapStringsSep " ; " builderLine builders;
in
{
  # Determinate Nix: append builder config to nix.custom.conf.
  # environment.etc.<name>.text uses lib.types.lines which concatenates
  # multiple module definitions automatically — no conflict with cachix module.
  environment.etc."nix/nix.custom.conf" = lib.mkIf isDeterminate {
    text = ''
      builders = ${buildersConf}
      builders-use-substitutes = true
      max-jobs = auto
      connect-timeout = 5
    '';
  };

  # Standard Nix (non-Determinate Linux hosts)
  nix.distributedBuilds = lib.mkIf (!isDeterminate) true;
  nix.buildMachines = lib.mkIf (!isDeterminate) builders;
  nix.settings = lib.mkIf (!isDeterminate) {
    builders-use-substitutes = true;
    max-jobs = "auto";
    trusted-users = [
      "root"
      user.name
    ];
  };
}
