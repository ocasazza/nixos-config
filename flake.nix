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
    consortium = {
      url = "github:olivecasazza/consortium";
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
        # GN9 has no TB cables connected — re-enable these when cabled
        # {
        #   subnet = "10.99.1"; # 10.99.1.0/30
        #   a = { host = "GN9CFLM92K-MBP"; iface = "en1"; };
        #   b = { host = "GJHC5VVN49-MBP"; iface = "en1"; };
        # }
        # {
        #   subnet = "10.99.2"; # 10.99.2.0/30
        #   a = { host = "GN9CFLM92K-MBP"; iface = "en2"; };
        #   b = { host = "CK2Q9LN7PM-MBA"; iface = "en2"; };
        # }
        {
          subnet = "10.99.3"; # 10.99.3.0/30
          a = {
            host = "CK2Q9LN7PM-MBA";
            iface = "en1";
          };
          b = {
            host = "GJHC5VVN49-MBP";
            iface = "en2"; # Receptacle 2 — physically connected to CK2 Receptacle 1
          };
        }
      ];

      # All hostnames participating in the cluster (includes WiFi-only nodes)
      thunderboltHosts = nixpkgs.lib.unique (
        [
          "GN9CFLM92K-MBP" # WiFi-only (no TB cables), re-add to links when cabled
          "L75T4YHXV7-MBA" # WiFi-only (no TB cables), re-add to links when cabled
        ]
        ++ nixpkgs.lib.concatMap (link: [
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
          modules = baseModules ++ [
            ./hosts/darwin/exo-cluster.nix
            { networking.hostName = hostname; }
          ];
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

            packages.deploy-cluster = pkgs.writeShellApplication {
              name = "deploy-cluster";
              runtimeInputs = [
                pkgs.git
                pkgs.nh
                pkgs.openssh
                inputs.consortium.packages.${system}.consortium-cli
              ];
              text = ''
                # deploy-cluster — build closures, copy via nix copy, activate via claw (consortium).
                # All remote traffic goes over Thunderbolt Bridge (*.tb hostnames).
                #
                # Usage: nix run .#deploy-cluster [hostname...]
                #   If no hostnames given, deploys to all cluster nodes.

                # ── Repo root ───────────────────────────────────────────────────────────
                if [[ -n ''${REPO_DIR:-} ]]; then
                  : # already set
                elif git -C "$PWD" rev-parse --show-toplevel &> /dev/null; then
                  REPO_DIR="$(git -C "$PWD" rev-parse --show-toplevel)"
                else
                  echo "error: cannot find nixos-config repo. Run from the repo root or set REPO_DIR." >&2
                  exit 1
                fi

                LOCAL_HOSTNAME="$(hostname -s)"
                SSH_USER="casazza"

                # ── Cluster membership (must match thunderboltLinks in flake.nix) ────────
                CLUSTER_NODES=(
                  "CK2Q9LN7PM-MBA"
                  "GJHC5VVN49-MBP"
                  "GN9CFLM92K-MBP"
                  "L75T4YHXV7-MBA"
                )

                tb_host() { echo "''${1}.tb"; }

                # Resolve reachable SSH target: prefer .tb, fall back to .local, then bare hostname (SSH config)
                resolve_host() {
                  local tb; tb="$(tb_host "$1")"
                  if ssh -o ConnectTimeout=3 -o BatchMode=yes "''${SSH_USER}@''${tb}" true &> /dev/null; then
                    echo "$tb"
                  elif ssh -o ConnectTimeout=3 -o BatchMode=yes "''${SSH_USER}@''${1}.local" true &> /dev/null; then
                    echo "''${1}.local"
                  elif ssh -o ConnectTimeout=3 -o BatchMode=yes "''${SSH_USER}@''${1}" true &> /dev/null; then
                    echo "''${1}"
                  else
                    echo ""
                  fi
                }

                TARGETS=("''${@:-''${CLUSTER_NODES[@]}}")
                LOG_DIR="$(mktemp -d /tmp/deploy-cluster.XXXXXX)"
                trap 'rm -rf "$LOG_DIR"' EXIT

                # Split into local vs remote
                REMOTE_NODES=()
                for host in "''${TARGETS[@]}"; do
                  [[ $host == "$LOCAL_HOSTNAME" ]] && continue
                  REMOTE_NODES+=("$host")
                done

                # ── 1. Commit & push ──────────────────────────────────────────────────────
                cd "$REPO_DIR"
                if ! git diff --quiet || ! git diff --cached --quiet; then
                  echo "==> Committing local changes..."
                  git add -A
                  git commit -m "chore: deploy cluster config $(date '+%Y-%m-%d %H:%M')"
                fi
                echo "==> Pushing..."
                git push

                # ── 2. Build all closures ─────────────────────────────────────────────────
                echo "==> Building closures for: ''${TARGETS[*]}"
                BUILD_ATTRS=()
                for host in "''${TARGETS[@]}"; do
                  BUILD_ATTRS+=(".#darwinConfigurations.''${host}.system")
                done
                nix build --no-link "''${BUILD_ATTRS[@]}"

                # ── 3. Copy closures to remote nodes over TB in parallel ───────────────────
                # Resolve SSH targets for all remote nodes (prefer .tb, fall back .local)
                declare -A RESOLVED_HOSTS
                if [[ ''${#REMOTE_NODES[@]} -gt 0 ]]; then
                  echo "==> Resolving remote node connectivity..."
                  for host in "''${REMOTE_NODES[@]}"; do
                    resolved="$(resolve_host "$host")"
                    if [[ -z $resolved ]]; then
                      echo "  SKIP (unreachable): $host"
                    else
                      RESOLVED_HOSTS["$host"]="$resolved"
                      echo "  $host → $resolved"
                    fi
                  done
                fi

                if [[ ''${#RESOLVED_HOSTS[@]} -gt 0 ]]; then
                  echo "==> Copying closures to remote nodes..."
                  COPY_PIDS=()
                  for host in "''${!RESOLVED_HOSTS[@]}"; do
                    target="''${RESOLVED_HOSTS[$host]}"
                    closure="$(nix path-info ".#darwinConfigurations.''${host}.system")"
                    echo "  copying ''${host} → ''${target} ..."
                    nix copy --no-check-sigs --to "ssh-ng://''${SSH_USER}@''${target}" "$closure" \
                      > "$LOG_DIR/''${host}.copy.log" 2>&1 &
                    COPY_PIDS+=($!)
                  done
                  for pid in "''${COPY_PIDS[@]}"; do wait "$pid"; done
                fi

                # ── 4. Activate ───────────────────────────────────────────────────────────

                # Local activation
                for host in "''${TARGETS[@]}"; do
                  if [[ $host == "$LOCAL_HOSTNAME" ]]; then
                    echo "==> Activating $host (local)..."
                    closure="$(nix path-info ".#darwinConfigurations.''${host}.system")"
                    sudo "''${closure}/sw/bin/darwin-rebuild" activate 2>&1 | tee "$LOG_DIR/''${host}.log"
                    echo "OK" > "$LOG_DIR/''${host}.status"
                    break
                  fi
                done

                # Remote activation via claw (consortium)
                if [[ ''${#RESOLVED_HOSTS[@]} -gt 0 ]]; then
                  echo "==> Activating remote nodes..."
                  ACTIVATE_PIDS=()
                  for host in "''${!RESOLVED_HOSTS[@]}"; do
                    target="''${RESOLVED_HOSTS[$host]}"
                    closure="$(nix path-info ".#darwinConfigurations.''${host}.system" 2> /dev/null || echo "")"
                    if [[ -z $closure ]]; then
                      echo "  SKIP (no closure): $host"
                      echo "SKIP" > "$LOG_DIR/''${host}.status"
                      continue
                    fi
                    echo "  → $host ($target): $closure"
                    ACTIVATE_CMD="set -euo pipefail; [ -e ''${closure} ] || { echo closure not found; exit 1; }; sudo ''${closure}/sw/bin/darwin-rebuild activate"
                    (
                      if claw -w "$target" -l "$SSH_USER" \
                        -t 5 -o "-o BatchMode=yes" \
                        -b -- bash -c "$ACTIVATE_CMD" \
                        > "$LOG_DIR/''${host}.log" 2>&1; then
                        echo "OK" > "$LOG_DIR/''${host}.status"
                      else
                        echo "FAILED" > "$LOG_DIR/''${host}.status"
                      fi
                    ) &
                    ACTIVATE_PIDS+=($!)
                  done
                  for pid in "''${ACTIVATE_PIDS[@]}"; do wait "$pid"; done
                fi

                # ── 5. Summary ────────────────────────────────────────────────────────────
                echo ""
                echo "==> Deploy summary:"
                FAILED=()
                SKIPPED=()
                for host in "''${TARGETS[@]}"; do
                  status="$(cat "$LOG_DIR/''${host}.status" 2> /dev/null || echo "UNKNOWN")"
                  case "$status" in
                    OK)     echo "  [OK]   $host" ;;
                    SKIP)   echo "  [SKIP] $host (unreachable)"; SKIPPED+=("$host") ;;
                    FAILED) echo "  [FAIL] $host (see $LOG_DIR/''${host}.log)"; FAILED+=("$host") ;;
                    *)      echo "  [???]  $host"; FAILED+=("$host") ;;
                  esac
                done

                echo ""
                [[ ''${#SKIPPED[@]} -gt 0 ]] && echo "==> Skipped: ''${SKIPPED[*]}"
                if [[ ''${#FAILED[@]} -eq 0 ]]; then
                  echo "==> All reachable nodes deployed and activated over Thunderbolt."
                else
                  echo "==> Failed: ''${FAILED[*]}"
                  exit 1
                fi
              '';
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
