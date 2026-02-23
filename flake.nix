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
    git-fleet = {
      url = "path:/Users/casazza/Repositories/git-fleet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      darwin,
      nix-homebrew,
      homebrew-bundle,
      homebrew-core,
      homebrew-cask,
      home-manager,
      nix4nvchad,
      nixpkgs,
      disko,
      ghostty,
      git-fleet,
      flake-parts,
      git-hooks-nix,
    }:
    let
      user = {
        # change to your preferred settings
        name = "casazza";
        fullName = "Olive Casazza";
        email = "olive.casazza@schrodinger.com";
      };
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      darwinSystems = [ "aarch64-darwin" ];
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ git-hooks-nix.flakeModule ];
      systems = linuxSystems ++ darwinSystems;

      perSystem =
        { config, system, ... }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pre-commit.settings = {
            hooks = {
              # Formatting with treefmt
              treefmt = {
                enable = true;
                name = "treefmt";
                description = "Format all files with treefmt";
                entry =
                  let
                    treefmt-wrapped = pkgs.writeShellScriptBin "treefmt-wrapped" ''
                      export PATH="${
                        pkgs.lib.makeBinPath [
                          pkgs.treefmt
                          pkgs.nixfmt-rfc-style
                          pkgs.shfmt
                          pkgs.nodePackages.prettier
                        ]
                      }:$PATH"
                      exec ${pkgs.treefmt}/bin/treefmt --fail-on-change
                    '';
                  in
                  "${treefmt-wrapped}/bin/treefmt-wrapped";
                pass_filenames = false;
              };
              # Nix
              deadnix.enable = true;
              # Conventional commits
              convco.enable = true;
              # YAML
              yamllint = {
                enable = true;
                name = "yamllint";
                entry = "${pkgs.yamllint}/bin/yamllint -c .yamllint.yaml";
                files = "\\.(yml|yaml)$";
                excludes = [ ".github/" ];
              };
              # JSON
              check-json = {
                enable = true;
                name = "check-json";
                entry = "${pkgs.jq}/bin/jq empty";
                files = "\\.json$";
                pass_filenames = true;
              };
            };
          };

          devShells.default =
            with pkgs;
            mkShell {
              nativeBuildInputs = with pkgs; [
                bashInteractive
                git
                statix
                deadnix
                nh
              ];
              shellHook = ''
                export EDITOR=nvim
                ${config.pre-commit.installationScript}
              '';
            };
        };

      flake = {
        darwinConfigurations = {
          macos = darwin.lib.darwinSystem {
            system = "aarch64-darwin";
            specialArgs = { user = user; } // inputs;
            modules = [
              home-manager.darwinModules.home-manager
              {
                home-manager = {
                  extraSpecialArgs = {
                    user = user;
                    inherit inputs;
                  };
                  useGlobalPkgs = true;
                  useUserPackages = true;
                };
              }
              nix-homebrew.darwinModules.nix-homebrew
              {
                nix-homebrew = {
                  enable = true;
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
              git-fleet.darwinModules.default
              ./hosts/darwin
            ];
          };
        };

        nixosConfigurations = nixpkgs.lib.genAttrs linuxSystems (
          system:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              user = user;
            } // inputs;
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
    };
}
