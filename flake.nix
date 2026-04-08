{
  description = "salt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/68d8aa3d661f0e6bd5862291b5bb263b2a6595c9"; # nixos-unstable with fixed exo 1.0.69 npmDepsHash
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
      url = "git+file:///Users/casazza/Repositories/schrodinger/opencode?ref=dev";
    };
    hermes = {
      url = "git+file:///Users/casazza/Repositories/schrodinger/hermes-agent?ref=schrodinger";
    };
    hippo = {
      url = "github:symposium-dev/hippo";
      flake = false;
    };
    # exo is in nixpkgs (v1.0.69) — no separate flake input needed
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

      # ── Thunderbolt point-to-point links ────────────────────────────────────
      # Each cable is a /30 subnet between two (host, interface) endpoints.
      # Side "a" gets .1, side "b" gets .2.  No L2 bridging — pure L3.
      # Subnet base is the first 3 octets; the 4th octet is always .0/30.
      thunderboltLinks = [
        {
          subnet = "10.99.1"; # 10.99.1.0/30
          a = {
            host = "GN9CFLM92K-MBP";
            iface = "en1";
          };
          b = {
            host = "GJHC5VVN49-MBP";
            iface = "en2";
          };
        }
        {
          subnet = "10.99.2"; # 10.99.2.0/30
          a = {
            host = "GN9CFLM92K-MBP";
            iface = "en2";
          };
          b = {
            host = "CK2Q9LN7PM-MBA";
            iface = "en2";
          };
        }
        {
          subnet = "10.99.3"; # 10.99.3.0/30
          a = {
            host = "CK2Q9LN7PM-MBA";
            iface = "en1";
          };
          b = {
            host = "GJHC5VVN49-MBP";
            iface = "en1";
          };
        }
      ];

      # All hostnames participating in the TB mesh
      thunderboltHosts = nixpkgs.lib.unique (
        nixpkgs.lib.concatMap (link: [
          link.a.host
          link.b.host
        ]) thunderboltLinks
      );

      # exo libp2p port (shared across cluster)
      exoPort = 52416;

      # For a given hostname, collect all its directly-connected link IPs
      # Returns: [ { ip, peerIp, peerHost, iface, subnet } ]
      linksForHost =
        hostname:
        nixpkgs.lib.concatMap (
          link:
          if link.a.host == hostname then
            [
              {
                ip = "${link.subnet}.1";
                peerIp = "${link.subnet}.2";
                peerHost = link.b.host;
                iface = link.a.iface;
                subnet = link.subnet;
              }
            ]
          else if link.b.host == hostname then
            [
              {
                ip = "${link.subnet}.2";
                peerIp = "${link.subnet}.1";
                peerHost = link.a.host;
                iface = link.b.iface;
                subnet = link.subnet;
              }
            ]
          else
            [ ]
        ) thunderboltLinks;

      # Build exo bootstrap peers for a host: /ip4/<peerTbIp>/tcp/<port>
      # Uses the first link IP to each peer (deterministic because thunderboltLinks is ordered)
      exoPeersFor =
        hostname:
        let
          links = linksForHost hostname;
        in
        map (l: "/ip4/${l.peerIp}/tcp/${toString exoPort}") links;

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
            inherit
              user
              isDeterminate
              hermes
              thunderboltLinks
              ;
            system = "aarch64-darwin";
            exoPeers = exoPeersFor hostname;
            exoNetwork = "thunderbolt";
            exoListenInterfaces = [ ]; # unused when exoNetwork = "thunderbolt"
            exoPackage = nixpkgs.legacyPackages.aarch64-darwin.exo;
            exoThunderboltHostname = hostname;
            exoThunderboltCluster = thunderboltHosts;
          }
          // inputs;
          modules = baseModules ++ [ ./hosts/darwin/exo-cluster.nix ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }:
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

            packages.deploy-cluster =
              let
                deps = [
                  pkgs.git
                  pkgs.nh
                  pkgs.openssh
                ];
              in
              pkgs.writeShellApplication {
                name = "deploy-cluster";
                runtimeInputs = deps;
                text = builtins.readFile ./scripts/deploy-cluster.sh;
              };

            apps.deploy-cluster = {
              type = "app";
              program = "${config.packages.deploy-cluster}/bin/deploy-cluster";
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
            // nixpkgs.lib.genAttrs thunderboltHosts (hostname: mkMachineConfig hostname);

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
