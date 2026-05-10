{
  description = "Olive Casazza's Nix Darwin and NixOS system configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # Track latest nixos-unstable (updated May 2026)

    # Surgical pin for opencode - tracking latest nixos-unstable for newest version
    nixpkgs-opencode.url = "github:nixos/nixpkgs/nixos-unstable";

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

    # Secrets management (sops-nix). Used by pdx-nxst-003 to decrypt
    # secrets/*.yaml at activation via its SSH host key (derived to
    # an age identity automatically). Already a transitive input via
    # git-fleet* but snowfall needs a direct handle to import
    # `nixosModules.default`.
    sops-nix = {
      url = "github:Mic92/sops-nix";
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

    # Flake inputs served from pdx-nxst-003's bare git mirrors at
    # `/srv/git/<name>.git`. We use `git+ssh://casazza@pdx-nxst-003/...`
    # for both fetch and push — anonymous git:// over port 9418 is
    # firewalled at the corp boundary, and unifying read/write on one
    # URL avoids the lockfile drift the old git-daemon split caused.
    # See CLAUDE.md `Cross-repo push targets` for the rationale.
    hermes = {
      url = "github:NousResearch/hermes-agent";
    };

    # Schrodinger fork of agentic-stack — portable .agent/ brain (skills,
    # memory, protocols, hooks, tools) + Schrodinger coordination patterns
    # + provider integration. Local repo mirrors the hermes pattern above.
    schrodinger-agentic-stack = {
      url = "git+file:///Users/casazza/Repositories/schrodinger/schrodinger-agentic-stack";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Bifrost — Go-based LLM gateway (~40x faster than LiteLLM, OpenAI-compatible,
    # 20+ providers, MCP gateway). Upstream ships its own flake exposing
    # packages.<sys>.bifrost-http and a (NixOS-only) services.bifrost module.
    # We use the package directly and write our own darwin module wrapping
    # launchd.user.agents (modules/darwin/bifrost/).
    #
    # NOT following our nixpkgs — bifrost's go.mod requires go >= 1.26.2,
    # but our pinned nixpkgs (Feb 2026) has go_1_26 = 1.26.1. Bifrost's
    # own staging-next nixpkgs has the newer go.
    bifrost = {
      url = "github:maximhq/bifrost?ref=transports/v1.5.0";
    };

    consortium = {
      url = "github:olivecasazza/consortium";
    };

    # Obsidian vault flake: provides vault-snapshot + vault-snapshot-watch
    # for the auto-snapshot launchd agent on darwin. Same git+ssh
    # transport as opencode/hermes above.
    obsidian-vault = {
      url = "git+ssh://casazza@pdx-nxst-001/srv/git/obsidian.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Shared SeaweedFS + JuiceFS + TiKV + macFUSE modules. Same flake is
    # consumed by ~/Repositories/schrodinger/git-fleet-runner so the
    # corp cluster (gfr-osx26-02/03/04) and the personal cluster
    # (pdx-nxst-003 + Macs) share one source of truth for the
    # storage stack.
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

      # outputs-builder: Expose additional packages beyond auto-discovered packages/
      # This is required because snowfall-lib's mkFlake doesn't automatically expose
      # packages from overlays to the packages.<system> attrset.
      outputs-builder = channels: {
        packages = {
          # Expose nixpkgs.skills for the skills CLI tool (open agent skills manager).
          skills = inputs.nixpkgs.legacyPackages.${channels.nixpkgs.system}.skills;
        };
      };

      # Overlays applied to all channels
      overlays = [
        # Make our claude-code package available as pkgs.claude-code
        (_final: prev: {
          claude-code = prev.callPackage ./packages/claude-code { };
        })
        # omlx — LLM inference server with continuous batching & SSD KV caching
        # for Apple Silicon. see packages/omlx/default.nix for why we use a
        # user-local venv rather than a full from-source build.
        (_final: prev: {
          omlx = prev.callPackage ./packages/omlx { };
        })
        # opencode-voice — local STT voice control for opencode (whisper.cpp)
        (_final: prev: {
          opencode-voice = prev.callPackage ./packages/opencode-voice { };
        })
        # twg — Atlassian Teamwork Graph CLI for Jira/Confluence/Bitbucket
        (_final: prev: {
          twg = prev.callPackage ./packages/twg { };
        })
        # agentic-stack — portable .agent/ brain (skills + memory + protocols
        # + tools) for AI coding harnesses (claude-code, opencode, hermes).
        # Sourced from the schrodinger-agentic-stack flake input (private fork
        # of upstream codejunkie99/agentic-stack v0.15.0). The overlay exposes
        # `pkgs.agentic-stack` for legacy consumers; new code should reference
        # `inputs.schrodinger-agentic-stack.packages.<system>.default` directly.
        (final: _prev: {
          agentic-stack =
            inputs.schrodinger-agentic-stack.packages.${final.stdenv.hostPlatform.system}.default;
        })
        # bifrost — high-performance LLM gateway (Go, 40x faster than LiteLLM).
        # Wrapper at packages/bifrost/ uses upstream's bifrost-http.nix with
        # a stub bifrost-ui (upstream's UI npmDepsHash drifted post-v1.5.0).
        # The /v1/* API works fully; only the localhost:8080/ui page is stubbed.
        # Pass `inputs` through callPackage so the package can resolve the
        # bifrost flake input (and its newer nixpkgs for Go 1.26.2).
        (_final: prev: {
          bifrost = prev.callPackage ./packages/bifrost { inherit inputs; };
        })
        # Expose nixpkgs.skills to pkgs for use in Home Manager packages.
        (final: _prev: {
          skills = inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system}.skills;
        })
        # NOTE: seaweedfs's overlay (which exposed pkgs.seaweedfs.{tikv,
        # tikv-pd}) is intentionally dropped — pdx-nxst-003 pivoted from
        # TiKV to Redis for JuiceFS metadata, so no consumer remains.
        # Re-add if some future host brings TiKV back.

        # Surgical opencode bump: stock nixpkgs (Feb 2026) ships 1.3.13
        # which predates the Azure provider and the current `/connect`
        # flow. Sourced from a newer nixpkgs rev (1.14.25) without
        # disturbing the rest of the closure.
        (final: _prev: {
          opencode = inputs.nixpkgs-opencode.legacyPackages.${final.stdenv.hostPlatform.system}.opencode;
        })
        # Silence nixpkgs's `pkgs.system` deprecation warning. The upstream
        # alias in pkgs/top-level/aliases.nix defines `system = warnAlias
        # "..." stdenv.hostPlatform.system` — the warning fires on any
        # attribute READ, even if no consumer in our local repo uses
        # `pkgs.system`. Some transitive flake input still does. Replacing
        # the alias with the same underlying value (no warnAlias wrapper)
        # is behavior-identical and shuts the noise up. Drop this overlay
        # the day all transitive consumers move to stdenv.hostPlatform.system.
        (final: _prev: {
          system = final.stdenv.hostPlatform.system;
        })
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
            sharedModules = [
              {
                # Disable home-manager's deprecated zsh module that emits warnings.
                disabledModules = [ "programs/zsh/deprecated.nix" ];
              }
              # Replacement module: provides deprecated options without warnings.
              (
                { config, lib, ... }:
                let
                  inherit (lib)
                    mkOption
                    types
                    mkIf
                    mkMerge
                    ;
                  cfg = config.programs.zsh;
                in
                {
                  options.programs.zsh = {
                    initExtraBeforeCompInit = mkOption {
                      default = "";
                      type = types.lines;
                      visible = false;
                      description = "Extra commands before compinit (Deprecated)";
                    };
                    initExtra = mkOption {
                      default = "";
                      type = types.lines;
                      visible = false;
                      description = "Extra commands (Deprecated)";
                    };
                    initExtraFirst = mkOption {
                      default = "";
                      type = types.lines;
                      visible = false;
                      description = "Commands at top of .zshrc (Deprecated)";
                    };
                  };
                  config.programs.zsh.initContent = mkMerge [
                    (mkIf (cfg.initExtraFirst != "") (lib.mkBefore cfg.initExtraFirst))
                    (mkIf (cfg.initExtraBeforeCompInit != "") (lib.mkOrder 550 cfg.initExtraBeforeCompInit))
                    (mkIf (cfg.initExtra != "") cfg.initExtra)
                  ];
                }
              )
            ];
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
        # Secrets management (sops-nix) on darwin. Mirrors the NixOS-side
        # import below (inputs.sops-nix.nixosModules.sops). Each Mac's
        # /etc/ssh/ssh_host_ed25519_key is auto-picked up via the
        # sops.age.sshKeyPaths default (services.openssh.enable is true in
        # hosts/darwin/default.nix). Per-host decryption further requires
        # each Mac's ssh-to-age pubkey to be added to .sops.yaml as an
        # `&host_<hostname>` anchor and each consumer secret to be
        # re-encrypted with `sops updatekeys` — see TODO(sops-darwin)
        # comments in hosts/darwin/default.nix.
        inputs.sops-nix.darwinModules.default
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
              consortium = inputs.consortium;
              obsidianVault = inputs.obsidian-vault;
              system = "aarch64-darwin";
            };
          }
        )
      ];

      # No NixOS systems live here anymore — they moved to
      # ~/Repositories/schrodinger/nixstation as part of the 2026-04-24
      # split. If a NixOS host ever lands back in this repo, restore
      # `systems.modules.nixos = [...]` with disko + sops-nix +
      # home-manager + seaweedfs imports per git history.

      # No aliases needed — snowfall auto-discovers shells/default
    };
}
