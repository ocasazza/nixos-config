{
  description = "salt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    # Disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Terminal
    ghostty = {
      url = "github:ghostty-org/ghostty";
    };
    # The rest are all MacOS
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
      url = "git+file:///Users/casazza/Repositories/schrodinger/opencode";
    };
    hermes = {
      url = "github:NousResearch/hermes-agent";
    };
    exo = {
      url = "github:exo-explore/exo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      darwin,
      nix-homebrew,
      homebrew-bundle,
      homebrew-core,
      homebrew-cask,
      home-manager,
      nixpkgs,
      disko,
      ghostty,
      # Even when we sleep
      # deadnix: skip
      git-fleet,
      # We will find you
      git-fleet-runner,
      hermes,
      exo,
      deploy-rs,
      flake-parts,
      git-hooks-nix,
      ...
    }:
    let
      user = {
        # change to your preferred settings
        name = "casazza";
        fullName = "Olive Casazza";
        email = "olive.casazza@schrodinger.com";
      };
      isDeterminate = true;
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      darwinSystems = [ "aarch64-darwin" ];

      # ── Exo cluster ──────────────────────────────────────────────────────────
      exoCluster = {
        "GN9CFLM92K-MBP" = 52416; # this machine
        "CK2Q9LN7PM-MBA" = 52416;
        "L75T4YHXV7-MBA" = 52416;
        "GJHC5VVN49-MBP" = 52416;
      };

      exoPeersFor =
        hostname:
        nixpkgs.lib.mapAttrsToList (host: port: "${host}.local:${toString port}") (
          nixpkgs.lib.filterAttrs (h: _: h != hostname) exoCluster
        );

      # ── Shared nix-darwin base modules ───────────────────────────────────────
      baseModules = [
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            extraSpecialArgs = {
              user = user;
              inherit inputs;
            };
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
          };
        }
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = false;
            user = user.name;
            taps = {
              "homebrew/homebrew-core" = homebrew-core;
              "homebrew/homebrew-cask" = homebrew-cask;
              "homebrew/homebrew-bundle" = homebrew-bundle;
            };
            mutableTaps = false;
            autoMigrate = true;
          };
        }
        git-fleet-runner.darwinModules.autopkgserver
      ]
      ++ nixpkgs.lib.optional (inputs ? opencode) inputs.opencode.darwinModules.default
      ++ [ ./hosts/darwin ];

      # Build a nix-darwin config for a given cluster hostname
      mkMachineConfig =
        hostname:
        darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            inherit user isDeterminate hermes;
            system = "aarch64-darwin";
            exoPeers = exoPeersFor hostname;
            exoListenInterfaces = [ "en0" ];
            exoPackage = exo.packages.aarch64-darwin.default;
          }
          // inputs;
          modules = baseModules ++ [ ./hosts/darwin/exo-cluster.nix ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }:
      {
        imports = [ git-hooks-nix.flakeModule ];
        systems = linuxSystems ++ darwinSystems;

        perSystem =
          { config, system, ... }:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            imports = [ ./nix/pre-commit.nix ];

            devShells.default =
              with pkgs;
              mkShell {
                nativeBuildInputs = with pkgs; [
                  bashInteractive
                  git
                  statix
                  deadnix
                  nh
                  deploy-rs.packages.${system}.default
                ];
                shellHook = ''
                  export EDITOR=nvim
                  ${config.pre-commit.installationScript}
                '';
              };
          };

        flake = {
          darwinConfigurations =
            let

              # Non-cluster config (no exo) for backward-compat aliases
              macosConfig = darwin.lib.darwinSystem {
                system = "aarch64-darwin";
                specialArgs = {
                  inherit user isDeterminate hermes;
                  system = "aarch64-darwin";
                }
                // inputs;
                modules = baseModules;
              };
            in
            {
              macos = macosConfig;
            }
            # Generate a config for every cluster node
            // nixpkgs.lib.mapAttrs (hostname: _: mkMachineConfig hostname) exoCluster;

          deploy = {
            nodes = {
              "GN9CFLM92K-MBP" = {
                hostname = "localhost";
                profiles.system = {
                  user = "root";
                  path = deploy-rs.lib.aarch64-darwin.activate.darwin self.darwinConfigurations."GN9CFLM92K-MBP";
                };
              };
              "CK2Q9LN7PM-MBA" = {
                hostname = "192.168.1.3";
                profiles.system = {
                  user = "root";
                  path = deploy-rs.lib.aarch64-darwin.activate.darwin self.darwinConfigurations."CK2Q9LN7PM-MBA";
                };
              };
              "GJHC5VVN49-MBP" = {
                hostname = "192.168.1.56";
                profiles.system = {
                  user = "root";
                  path = deploy-rs.lib.aarch64-darwin.activate.darwin self.darwinConfigurations."GJHC5VVN49-MBP";
                };
              };
              "L75T4YHXV7-MBA" = {
                hostname = "L75T4YHXV7-MBA.local";
                profiles.system = {
                  user = "root";
                  path = deploy-rs.lib.aarch64-darwin.activate.darwin self.darwinConfigurations."L75T4YHXV7-MBA";
                };
              };
            };
          };

          nixosConfigurations = nixpkgs.lib.genAttrs linuxSystems (
            system:
            nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = {
                inherit user isDeterminate;
              }
              // inputs;
              modules = [
                disko.nixosModules.disko
                home-manager.nixosModules.home-manager
                {
                  home-manager = {
                    extraSpecialArgs = {
                      user = user;
                      inherit inputs;
                    };
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    users.${user.name} = import ./modules/nixos/home-manager.nix;
                  };
                  environment.systemPackages = [
                    ghostty.packages.x86_64-linux.default
                  ];
                }
                ./hosts/nixos
              ];
            }
          );
        };
      }
    );
}
