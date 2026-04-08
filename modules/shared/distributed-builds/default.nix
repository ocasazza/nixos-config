# Distributed Nix builds across the Thunderbolt cluster.
#
# Each cluster node acts as a remote builder for the others, offloading
# long builds (node_modules, Python venvs, etc.) across all machines.
# SSH uses .local mDNS names so macOS routes over the fastest available
# interface (Thunderbolt Bridge when connected, WiFi fallback otherwise).
#
# Requirements on each builder node:
#   - The initiating machine's SSH public key in ~/.ssh/authorized_keys
#   - `nix-daemon` trusted-users includes casazza (set via trusted-users below)
#   - The builder must have the same Nix version (Determinate Nix on all nodes)
{
  lib,
  isDeterminate,
  user,
  ...
}:
let
  # All cluster nodes as potential builders.
  # system = aarch64-darwin for all Apple Silicon Macs.
  # maxJobs: leave 2 cores free for the local machine's own work.
  # speedFactor: all nodes treated equally — adjust if one is significantly faster.
  builders = [
    {
      hostName = "GN9CFLM92K-MBP.local";
      system = "aarch64-darwin";
      sshUser = "casazza";
      sshKey = "/Users/casazza/.ssh/id_ed25519";
      maxJobs = 6;
      speedFactor = 1;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    }
    {
      hostName = "CK2Q9LN7PM-MBA.local";
      system = "aarch64-darwin";
      sshUser = "casazza";
      sshKey = "/Users/casazza/.ssh/id_ed25519";
      maxJobs = 6;
      speedFactor = 1;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostName = "GJHC5VVN49-MBP.local";
      system = "aarch64-darwin";
      sshUser = "casazza";
      sshKey = "/Users/casazza/.ssh/id_ed25519";
      maxJobs = 6;
      speedFactor = 1;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
    {
      hostName = "L75T4YHXV7-MBA.local";
      system = "aarch64-darwin";
      sshUser = "casazza";
      sshKey = "/Users/casazza/.ssh/id_ed25519";
      maxJobs = 6;
      speedFactor = 1;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
    }
  ];

  # Format a builder attrset as a nix.conf builders line:
  # ssh://user@host system key maxJobs speed features
  builderLine =
    b:
    "ssh://${b.sshUser}@${b.hostName} ${b.system} ${b.sshKey} ${toString b.maxJobs} ${toString b.speedFactor} ${lib.concatStringsSep "," b.supportedFeatures}";

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
