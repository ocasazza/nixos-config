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

      # Auto-discover all home modules in modules/home/. Snowfall already
      # exposes these as `homeModules.<name>`, but that output is only
      # available on the built flake — we can't reference it during
      # evaluation of `mkFlake` itself. Instead we read the directory
      # ourselves and import each default.nix, mirroring snowfall's logic.
      # Result: a list ready to drop into `home-manager.sharedModules`.
      #
      # Tolerate the directory being absent or untracked: when nothing
      # has been added under modules/home/ yet, `readDir` would fail
      # with "path not tracked by Git". Returning an empty list there
      # lets the flake still evaluate cleanly.
      homeModulePaths =
        if builtins.pathExists ./modules/home then
          builtins.attrNames (
            lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir ./modules/home)
          )
        else
          [ ];
      homeModules = builtins.map (name: import (./modules/home + "/${name}")) homeModulePaths;
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
      ];

      # ── Darwin systems ──────────────────────────────────────────────────
      systems.modules.darwin = [
        inputs.home-manager.darwinModules.home-manager
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
            backupFileExtension = "bak";
            # Auto-applied to every home-manager user. Modules discovered
            # from modules/home/<name>/default.nix at flake-eval time.
            sharedModules = homeModules;
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
            # Auto-applied to every home-manager user. Modules discovered
            # from modules/home/<name>/default.nix at flake-eval time.
            sharedModules = homeModules;
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
