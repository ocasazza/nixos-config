{
  pkgs,
  user,
  config,
  opencode,
  ...
}:

let
  wallpaper = ../../modules/darwin/files/AFRC2017-0233-007-large.jpg;
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/darwin/power
    ../../modules/shared
    ../../modules/shared/cachix
    ../../modules/shared/distributed-builds
    ../../modules/shared/hermes
  ];

  local.hermes = {
    enable = true;
    claw3d.enable = true;
    voice.enable = true;
    hippo.enable = true;

    # Hybrid: main agent on Claude Opus 4.6 via Vertex (unchanged)
    # Subagent / MCP coding agent: Qwen3 Coder Next 8bit via exo cluster
    # Both providers registered — delegation + coding auxiliary use exo,
    # vision/web/compression stay on Vertex Haiku.
    localModel = "mlx-community/Qwen3-Coder-Next-8bit";
    exo.enable = true;
    exo.apiPort = 52415;
    delegation.useVertexProxy = false; # coding subagent → exo
    auxiliary.useVertexProxy = true; # vision/web/approval stay on Vertex Haiku

    soulMd = ''
      You are Hermes Agent running on a Schrodinger engineering workstation (Apple Silicon Mac,
      nix-darwin). You are helpful, direct, and technically precise. Prefer concise responses
      unless depth is needed. Admit uncertainty rather than guessing.

      ## Environment

      - OS: macOS (nix-darwin, aarch64-darwin). All system config is declarative Nix — never
        suggest imperative installs with brew or pip when a Nix solution exists.
      - Shell: zsh. Persistent shell is enabled; CWD and env vars survive between tool calls.
      - Package manager: Nix flakes + home-manager. Use `nh darwin switch` to rebuild.
      - Nix flake: `~/.config/nixos-config` (git repo). Configuration is in
        `modules/shared/`, `modules/darwin/`, and `hosts/darwin/default.nix`.
      - Cluster: 3-node Thunderbolt mesh (GN9CFLM92K-MBP, GJHC5VVN49-MBP, CK2Q9LN7PM-MBA).
        Deploy with `nix run .#deploy-cluster` from `~/.config/nixos-config`.
      - AI stack: hermes-agent (Schrodinger fork), opencode (Schrodinger fork), claude-code —
        all routed through Vertex AI proxy at https://vertex-proxy.sdgr.app.
        Auth via `gcloud auth print-identity-token` written to `~/.hermes/.env`.
      - Distributed inference: exo cluster (gfr-osx26-02/03), OpenAI-compatible API at
        http://localhost:52415/v1. Subagent/coding model: mlx-community/Qwen3-Coder-Next-8bit.
        Access via `just tunnel` from git-fleet-runner to forward the exo API locally.

      ## Hippo Memory

      Hippo is your long-term insight store. Use it actively:

      - **Search first**: before starting any non-trivial task, call `mcp_hippo_search_insights`
        with relevant terms (project name, technology, username). Do this proactively.
      - **Record at checkpoints**: after debugging something tricky, making a design decision,
        discovering an undocumented behavior, or learning a user preference — record it with
        `mcp_hippo_record_insight`. Use specific situation tags like
        `["nix", "darwin", "flakes"]` or `["user:casazza", "preferences"]`.
      - **Reinforce**: upvote insights that helped; downvote ones that were wrong or stale.
      - **Generalize**: if an insight applies more broadly than you first thought, modify it.
      - Importance guide: 0.1–0.3 minor/niche, 0.4–0.6 solid patterns, 0.7–0.9 hard-won
        lessons and strong preferences, 1.0 invariants that must never be forgotten.

      ## Working with This Nix Config

      - Always validate changes with `nix eval` before suggesting a rebuild.
        Example: `nix eval --impure --expr '(builtins.getFlake "git+file:///Users/casazza/.config/nixos-config?shallow=1").darwinConfigurations.GN9CFLM92K-MBP.config.<attr>'`
      - Use `nh darwin switch` (not `darwin-rebuild`) for rebuilds. It wraps darwin-rebuild
        with better UX and uses `NH_DARWIN_FLAKE` from the environment.
      - Pre-commit hooks run automatically on `git commit`: treefmt (nixfmt, shfmt, prettier),
        deadnix, yamllint, check-json. Fix formatter issues before committing.
      - SOPS secrets are age-encrypted. Key is at `~/.config/sops/age/keys.txt`.
        Edit secrets with `sops secrets/fleet.env` or `sops secrets/opencode.env`.
      - Private flake inputs (git-fleet, git-fleet-runner, opencode, hermes) require SSH
        agent with `~/.ssh/id_ed25519` loaded.

       ## File System

       - HOME is `/Users/casazza`. NEVER use `/root/` — it does not exist on macOS.
       - Write temporary files to `/tmp/` or `~/` — never to `/root/`, `/home/`, or
         Linux-style paths.
       - When writing analysis output, use `~/` prefix or the current project directory.
       - macOS does not have `/usr/local/bin` by default under nix-darwin — use
         `$(which cmd)` or full nix store paths if a command isn't on PATH.

       ## Skills and Delegation

       - Use `delegate_task` for parallel workstreams or tasks that benefit from a fresh
         isolated context (refactoring, research, code review). Subagents run Haiku.
       - Subagents also run on macOS — pass the same filesystem constraints above when
         delegating: no /root/, use ~/tmp/ or /tmp/ for scratch files.
       - Use skills when available: github-pr-workflow, systematic-debugging,
         subagent-driven-development, plan, research-paper-writing.
       - Save reusable workflows as skills via `skill_manage` rather than repeating them.
    '';
  };

  # Opencode + Claude Code Vertex AI proxy
  programs.opencode = {
    enable = true;
    package = opencode.packages.${pkgs.system}.default;
    managedConfig = {
      share = "disabled";
      enabled_providers = [ "anthropic" ];
      provider.anthropic.options.baseURL = "https://vertex-proxy.sdgr.app/v1";
    };
    vertex = {
      enable = true;
      projectId = "vertex-code-454718";
      region = "us-east5";
      baseURL = "https://vertex-proxy.sdgr.app/v1";
    };
    apiKeyHelper = true;
  };

  # Enable autopkgserver for Fleet GitOps package building
  services.autopkgserver = {
    enable = true;
    # Point to git-fleet repo for recipe overrides (development machine only)
    recipeOverrideDirs = "/Users/${user.name}/Repositories/schrodinger/git-fleet/lib/software";
  };

  # Set desktop wallpaper and Claude Code API key helper
  system.activationScripts.postActivation.text = ''
    # Set wallpaper (timeout to avoid hanging on headless/lid-closed machines)
    timeout 5 sudo -u ${user.name} osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"' 2>/dev/null || true

    # Set up Claude Code get-iam-token.sh helper for Vertex AI proxy
    echo "setting up Claude Code API key helper..." >&2
    mkdir -p /Users/${user.name}/.claude
    cat > /Users/${user.name}/.claude/get-iam-token.sh << 'TOKENHELPER'
    #!/usr/bin/env bash
    set -euo pipefail
    echo $(gcloud auth print-identity-token 2>/dev/null)
    TOKENHELPER
    chmod +x /Users/${user.name}/.claude/get-iam-token.sh
    chown -R ${user.name} /Users/${user.name}/.claude
  '';

  # Load Fleet secrets into user's shell environment
  # Creates a .fleet_secrets file in the user's home directory
  system.activationScripts.fleetSecrets.text = ''
    echo "Loading Fleet MDM secrets..."
    FLEET_SECRETS_FILE="${config.sops.secrets.fleet.path}"
    USER_ENV_FILE="/Users/${user.name}/.fleet_secrets"

    if [ -f "$FLEET_SECRETS_FILE" ]; then
      cp "$FLEET_SECRETS_FILE" "$USER_ENV_FILE"
      chown ${user.name}:staff "$USER_ENV_FILE"
      chmod 600 "$USER_ENV_FILE"
      echo "Fleet secrets loaded to $USER_ENV_FILE"
    else
      echo "Warning: Fleet secrets file not found at $FLEET_SECRETS_FILE"
    fi
  '';

  # Tiling window manager (no SIP disable needed)
  services.aerospace = {
    enable = true;
    settings = {
      # Normalizations
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      # Mouse follows focus
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
      # Gaps
      gaps = {
        inner.horizontal = 1;
        inner.vertical = 1;
        outer.left = 1;
        outer.right = 1;
        outer.top = 1;
        outer.bottom = 1;
      };
      mode.main.binding = {
        # Focus
        "alt-h" = "focus left";
        "alt-j" = "focus down";
        "alt-k" = "focus up";
        "alt-l" = "focus right";
        # Move windows
        "alt-shift-h" = "move left";
        "alt-shift-j" = "move down";
        "alt-shift-k" = "move up";
        "alt-shift-l" = "move right";
        # Resize
        "alt-shift-minus" = "resize smart -50";
        "alt-shift-equal" = "resize smart +50";
        # Layout
        "alt-slash" = "layout tiles horizontal vertical";
        "alt-comma" = "layout accordion horizontal vertical";
        "alt-f" = "fullscreen";
        # Workspaces
        "alt-1" = "workspace 1";
        "alt-2" = "workspace 2";
        "alt-3" = "workspace 3";
        "alt-4" = "workspace 4";
        "alt-5" = "workspace 5";
        # Move to workspace
        "alt-shift-1" = "move-node-to-workspace 1";
        "alt-shift-2" = "move-node-to-workspace 2";
        "alt-shift-3" = "move-node-to-workspace 3";
        "alt-shift-4" = "move-node-to-workspace 4";
        "alt-shift-5" = "move-node-to-workspace 5";
        # Service
        "alt-shift-semicolon" = "mode service";
      };
      mode.service.binding = {
        "esc" = [
          "reload-config"
          "mode main"
        ];
        "r" = [
          "flatten-workspace-tree"
          "mode main"
        ];
        "f" = [
          "layout floating tiling"
          "mode main"
        ];
        "backspace" = [
          "close-all-windows-but-current"
          "mode main"
        ];
      };
    };
  };

  # Pastel purple window borders
  services.jankyborders = {
    enable = true;
    active_color = "0xffb4a7d6";
    inactive_color = "0x00000000";
    width = 5.0;
  };

  # Enable SSH (Remote Login) so this machine is reachable as a remote builder
  # and discoverable via mDNS (.local) by other cluster nodes.
  services.openssh.enable = true;

  # Determinate Nix manages the daemon, nix binary, and nix.conf.
  # Don't let nix-darwin override it with a nixpkgs nix package.
  # See: https://docs.determinate.systems/getting-started/individual-install/#with-nix-darwin
  nix.enable = false;

  environment.systemPackages = with pkgs; import ../../modules/shared/packages.nix { inherit pkgs; };

  # Set system-wide environment variables
  environment.variables = {
    # NH Darwin flake configuration — use the hostname-specific config
    # which includes exo cluster membership and all Schrodinger overrides
    NH_DARWIN_FLAKE = ".#darwinConfigurations.${config.networking.hostName}";
    # SOPS key file location
    SOPS_AGE_KEY_FILE = "/Users/${user.name}/.config/sops/age/keys.txt";
    # Nix configuration
    NIXPKGS_ALLOW_UNFREE = "1";
    # Git SSH configuration
    GIT_SSH_COMMAND = "ssh -i /Users/${user.name}/.ssh/id_ed25519 -o IdentitiesOnly=yes";
    # Claude Code Vertex AI proxy
    CLAUDE_CODE_USE_VERTEX = "1";
    CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
    CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
    ANTHROPIC_VERTEX_PROJECT_ID = "vertex-code-454718";
    ANTHROPIC_VERTEX_BASE_URL = "https://vertex-proxy.sdgr.app/v1";
    CLOUD_ML_REGION = "us-east5";
  };

  # Auto-load direnv for Claude Code (avoids needing nix develop)
  # Uses programs.zsh.shellInit for all zsh shells (interactive and non-interactive)
  programs.zsh.shellInit = ''
    # Load Fleet MDM secrets
    if [ -f "$HOME/.fleet_secrets" ]; then
      set -a
      source "$HOME/.fleet_secrets"
      set +a
    fi

    # Set up Google Cloud credentials for Claude Code Vertex AI proxy
    if command -v gcloud >/dev/null 2>&1; then
      export GOOGLE_APPLICATION_CREDENTIALS_JSON="$(gcloud auth print-access-token 2>/dev/null || echo "")"
    fi

    if command -v direnv >/dev/null 2>&1; then
      if [ -n "$CLAUDECODE" ]; then
        eval "$(direnv hook zsh)"
        # Trigger direnv to load .envrc in current directory
        if [ -f ".envrc" ]; then
          _direnv_hook
        fi
      fi
    fi
  '';

  security.pam.services.sudo_local.enable = false;

  # Passwordless sudo for casazza — enables non-interactive cluster deploys
  environment.etc."sudoers.d/casazza-nopasswd".text = "${user.name} ALL=(ALL) NOPASSWD: ALL\n";

  # BeyondTrust blocks /etc/pam.d writes
  # security.pam.services.sudo_local = {
  #   enable = true;
  #   reattach = true;
  #   touchIdAuth = true;
  #   watchIdAuth = true;
  # };

  system = {
    stateVersion = 5;
    primaryUser = user.name;
    #checks.verifyNixPath = false;
    # https://mynixos.com/nix-darwin/options/system.defaults
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;
        AppleICUForce24HourTime = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;

        KeyRepeat = 2; # 120, 90, 60, 30, 12, 6, 2
        InitialKeyRepeat = 15; # 120, 94, 68, 35, 25, 15

        # unavailable preferences can be accessed using quotes
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
        # Prevent double-click title bar from filling screen (fights AeroSpace)
        # AppleActionOnDoubleClick removed — option no longer exists in nix-darwin
      };

      CustomUserPreferences = {
        "com.apple.Spotlight" = {
          "com.apple.Spotlight MenuItemHidden" = 1;
        };
        NSGlobalDomain = {
          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
        };
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.screencapture" = {
          location = "~/Screenshots";
          type = "png";
        };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        "com.apple.WindowManager" = {
          GloballyEnabled = false;
          EnableStandardClickToShowDesktop = false;
          EnableTilingByEdgeDrag = false;
          EnableTilingOptionAccelerator = false;
          EnableTopTilingByEdgeDrag = false;
          EnableTiledWindowMargins = false;
        };
        "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;
      };

      dock = {
        # the rest of the dock settings are in modules/darwin/home-manager.nix
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.001;
        mru-spaces = false;
        show-recents = false;
        tilesize = 48;
        appswitcher-all-displays = true;
        dashboard-in-overlay = false;
        enable-spring-load-actions-on-all-items = false;
        expose-animation-duration = 0.2;
        expose-group-apps = false;
        launchanim = true;
        mineffect = "genie";
        minimize-to-application = false;
        mouse-over-hilite-stack = true;
        orientation = "bottom";
        show-process-indicators = true;
        showhidden = false;
        static-only = true;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };

      finder = {
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirst = true;
        # When performing a search, search the current folder by default
        AppleShowAllExtensions = true;
        FXDefaultSearchScope = "SCcf";
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowPathbar = true;
        ShowRemovableMediaOnDesktop = true;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };
  };
}
