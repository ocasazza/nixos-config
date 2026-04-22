{
  description = "salt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/68d8aa3d661f0e6bd5862291b5bb263b2a6595c9"; # nixos-unstable with fixed exo 1.0.69 npmDepsHash

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Terminal
    ghostty = {
      url = "github:ghostty-org/ghostty";
    };

    # macOS
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    nix4nvchad = {
      url = "github:nix-community/nix4nvchad";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Welcome to your life
    git-fleet = {
      url = "git+ssh://git@github.com/schrodinger/git-fleet";
    };
    # Theres no turning back
    git-fleet-runner = {
      url = "git+ssh://git@github.com/schrodinger/git-fleet-runner";
    };

    opencode = {
      url = "git+file:///Users/casazza/Repositories/schrodinger/opencode?ref=dev";
    };

    hermes = {
      url = "git+file:///Users/casazza/Repositories/schrodinger/hermes-agent?ref=schrodinger";
    };

    hippo = {
      url = "github:symposium-dev/hippo";
      flake = false;
    };

    consortium = {
      url = "github:olivecasazza/consortium";
    };

    # Obsidian vault flake: provides vault-snapshot + vault-snapshot-watch
    # for the auto-snapshot launchd agent on darwin.
    obsidian-vault = {
      url = "git+file:///Users/casazza/Repositories/ocasazza/obsidian";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Shared SeaweedFS + JuiceFS + TiKV + macFUSE modules. Same flake is
    # consumed by ~/Repositories/schrodinger/git-fleet-runner so the
    # corp cluster (gfr-osx26-02/03/04) and the personal cluster (luna +
    # Macs) share one source of truth for the storage stack.
    seaweedfs = {
      url = "git+ssh://git@github.com/schrodinger/seaweedfs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;
        src = ./.;

        snowfall = {
          namespace = "salt";
          meta = {
            name = "salt";
            title = "Salt — NixOS/nix-darwin config";
          };
        };
      };

      # NOTE: home-manager wiring is now handled by snowfall homes.
      # Snowfall auto-discovers `homes/<arch>/<user>[@host]/default.nix`
      # and:
      #   1. Exposes them as `homeConfigurations.<user>@<host>`
      #   2. Generates per-system `home-manager.users.<user>` modules
      #      that self-gate on host/system match
      #   3. Auto-discovers every `modules/home/<name>/default.nix` and
      #      adds them as `home-manager.sharedModules`
      #
      # Cross-platform HM logic lives in `homes/<arch>/casazza/` (no
      # @host means apply to every system on that arch).
    in
    lib.mkFlake {
      channels-config = {
        allowUnfree = true;
        allowBroken = true;
      };

      # Overlays applied to all channels
      overlays = [
        # Make our claude-code package available as pkgs.claude-code
        (_final: prev: {
          claude-code = prev.callPackage ./packages/claude-code { };
        })
        # Expose pkgs.tikv + pkgs.tikv-pd to NixOS systems (Linux-only;
        # the overlay is a no-op on darwin since meta.platforms gates
        # the packages out).
        inputs.seaweedfs.overlays.default
      ];

      # ── Darwin systems ──────────────────────────────────────────────────
      systems.modules.darwin = [
        inputs.home-manager.darwinModules.home-manager
        {
          home-manager = {
            extraSpecialArgs = {
              inherit inputs;
              # Snowfall passes `user` as a string to homes; the rest of
              # the codebase wants an attrset. We override here so any
              # NixOS/darwin module that takes `user` as specialArg gets
              # the rich attrset.
              user = {
                name = "casazza";
                fullName = "Olive Casazza";
                email = "olive.casazza@schrodinger.com";
              };
            };
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            # sharedModules is no longer needed — snowfall auto-applies
            # everything in modules/home/ via its home system-modules.
          };
        }
        inputs.nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = false;
            user = "casazza";
            taps = {
              "homebrew/homebrew-core" = inputs.homebrew-core;
              "homebrew/homebrew-cask" = inputs.homebrew-cask;
              "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
            };
            mutableTaps = false;
            autoMigrate = true;
          };
        }
        inputs.git-fleet-runner.darwinModules.autopkgserver
        # Shared storage stack (matches gfr's wiring of the same modules)
        inputs.seaweedfs.darwinModules.seaweedfs
        inputs.seaweedfs.darwinModules.juicefs
        inputs.seaweedfs.darwinModules.macfuse
        # Pass specialArgs that existing modules expect
        (
          { ... }:
          {
            _module.args = {
              user = {
                name = "casazza";
                fullName = "Olive Casazza";
                email = "olive.casazza@schrodinger.com";
              };
              isDeterminate = true;
              hermes = inputs.hermes;
              hippo = inputs.hippo;
              opencode = inputs.opencode;
              consortium = inputs.consortium;
              obsidianVault = inputs.obsidian-vault;
              system = "aarch64-darwin";
            };
          }
        )
      ]
      ++ inputs.nixpkgs.lib.optional (inputs ? opencode) inputs.opencode.darwinModules.default;

      # ── NixOS systems ──────────────────────────────────────────────────
      systems.modules.nixos = [
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.home-manager
        # Shared storage stack — luna runs the full stack (seaweedfs +
        # tikv); macs are JuiceFS clients only via the darwin modules.
        inputs.seaweedfs.nixosModules.seaweedfs
        inputs.seaweedfs.nixosModules.juicefs
        inputs.seaweedfs.nixosModules.tikv
        {
          home-manager = {
            extraSpecialArgs = {
              inherit inputs;
              user = {
                name = "casazza";
                fullName = "Olive Casazza";
                email = "olive.casazza@schrodinger.com";
              };
            };
            useGlobalPkgs = true;
            useUserPackages = true;
            # sharedModules is no longer needed — snowfall auto-applies
            # everything in modules/home/ via its home system-modules.
          };
        }
        (
          { ... }:
          {
            _module.args = {
              user = {
                name = "casazza";
                fullName = "Olive Casazza";
                email = "olive.casazza@schrodinger.com";
              };
              isDeterminate = false;
            };
          }
        )
      ];

      # No aliases needed — snowfall auto-discovers shells/default
    };
}
