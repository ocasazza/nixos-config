{
  pkgs,
  user,
  config,
  opencode,
  consortium,
  ...
}:

let
  wallpaper = ../../modules/_darwin-support/files/AFRC2017-0233-007-large.jpg;
  # Sketchybar's pixel height. AeroSpace's `gaps.outer.top` is set to
  # this same value so tiled windows start beneath the bar instead of
  # being clipped by it. Adjust here to keep both in sync.
  sketchybarHeight = 28;
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/darwin/power
    ../../modules/shared
    ../../modules/shared/cachix
    ../../modules/shared/distributed-builds
    ../../modules/shared/hermes
    ../../modules/shared/obsidian-vault
  ];

  # ── sops-nix (darwin) ───────────────────────────────────────────────
  # Secrets materialization at launchd activation. Each Mac's
  # /etc/ssh/ssh_host_ed25519_key is auto-used as the age identity via
  # sops.age.sshKeyPaths' default (services.openssh.enable = true below).
  #
  # TODO(sops-darwin): none of the four Macs
  # (CK2Q9LN7PM-MBA / GJHC5VVN49-MBP / GN9CFLM92K-MBP / L75T4YHXV7-MBA)
  # have `&host_<hostname>` anchors in .sops.yaml yet, and the secret
  # files below are only encrypted to admin_olive + host_luna. Until
  # each Mac contributes its ssh-to-age pubkey:
  #
  #     ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
  #
  # and the secrets are re-encrypted with `sops updatekeys`, the
  # launchd sops-install-secrets service will log "no key could decrypt
  # the data" at activation. Eval still succeeds — the validation is
  # runtime-only. Consumers are written to tolerate this:
  #   * fleet.env → the system.activationScripts.fleetSecrets block
  #     below guards on `if [ -f "$FLEET_SECRETS_FILE" ]`.
  #   * litellm-key-claude-code-darwin → cloudPassthrough=true on the
  #     programs.claude-code block below means the wrapper never reads
  #     the file anyway.
  sops = {
    defaultSopsFile = ../../secrets/fleet.env;
    defaultSopsFormat = "dotenv";
    # age.sshKeyPaths defaults to [ /etc/ssh/ssh_host_ed25519_key ] which
    # is exactly what we want — no override needed.
    secrets = {
      # Fleet MDM env file — whole file is the payload, consumed by the
      # fleetSecrets activation script below which copies the decrypted
      # file verbatim to ~/.fleet_secrets and sources it from zsh.
      fleet = {
        sopsFile = ../../secrets/fleet.env;
        format = "dotenv";
      };
      # LiteLLM virtual key for the darwin claude-code client. Yaml
      # secret with a single `litellm_api_key` scalar — sops-nix writes
      # just the value to /run/secrets/litellm-key-claude-code-darwin.
      # Mirrors the declaration on luna
      # (systems/x86_64-linux/luna/default.nix).
      litellm-key-claude-code-darwin = {
        sopsFile = ../../secrets/litellm-key-claude-code-darwin.yaml;
        format = "yaml";
        key = "litellm_api_key";
      };
    };
  };

  local.obsidianVault = {
    enable = true;
    vaultPath = "/Users/${user.name}/Repositories/ocasazza/obsidian/vault";
    reingestAuto.enable = true;
  };

  # Mac-side OTel collector daemon. Pushes hostmetrics + opencode
  # pipeline logs + reingest gauges to luna's OTLP intake at
  # luna:4317. Replaces the old "Macs send nothing" gap that left the
  # Grafana reingest tiles empty. See modules/darwin/observability.
  local.darwinObservability.enable = true;

  local.hermes = {
    enable = true;
    claw3d.enable = true;
    voice.enable = true;
    hippo.enable = true;
    hippo.obsidianSync = {
      enable = true;
      vaultPath = "/Users/${user.name}/Repositories/ocasazza/obsidian/vault";
    };

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

  # Claude Code routed through the LiteLLM proxy on luna. Identical
  # across every darwin host in this fleet, so the per-host files at
  # systems/aarch64-darwin/<host>/default.nix only need to override
  # what's actually host-specific (hostname, exo peers, distributed-
  # builds toggle).
  #
  # cloudPassthrough keeps the apiKeyHelper path alive so Claude Code's
  # default (Opus via vertex-proxy) still works — the request goes
  # `darwin -> luna:4000/vertex/v1 -> vertex-proxy` instead of
  # `darwin -> vertex-proxy` directly. LiteLLM doesn't add any auth
  # state for cloud; it just forwards the gcloud id-token. Explicit
  # model-name selection (e.g. `claude --model coder-local`) routes
  # via LiteLLM's OpenAI-compat router to luna's vLLM.
  #
  # Telemetry is off here — LiteLLM's OTEL callbacks cover per-call
  # tracing into Phoenix with richer attribution; the client telemetry
  # would duplicate spans.
  #
  # virtualKeyFile resolves to /run/secrets/litellm-key-claude-code-darwin
  # via the sops.secrets declaration below. Until each darwin host's
  # ssh-to-age pubkey is added to .sops.yaml as `&host_<hostname>` and
  # the yaml is `sops updatekeys`d, decryption at launchd activation
  # will fail — but cloudPassthrough=true means the wrapper never reads
  # the file, so claude-code still works against vertex-proxy in the
  # meantime. See TODO(sops-darwin) below.
  programs.claude-code = {
    enable = true;
    model = "claude-opus-4-7";
    litellm = {
      enable = true;
      endpoint = "http://luna.local:4000";
      virtualKeyFile = "/run/secrets/litellm-key-claude-code-darwin";
      defaultGroup = "coder-cloud-claude";
      cloudPassthrough = true;
    };
    telemetry.enable = false;
  };

  # Opencode + Claude Code Vertex AI proxy
  programs.opencode = {
    enable = true;
    package = opencode.packages.${pkgs.system}.default;
    # NOTE: `programs.opencode.telemetry` was added to `hosts/darwin/default.nix`
    # in b3918f1 ("feat(darwin): enable opencode OTLP export to Phoenix on luna")
    # but the opencode flake input pinned on `main` (dev @ 171f89f) does not
    # yet expose that option — only `enable`, `package`, `managedConfig`,
    # `vertex`, `secrets`, and `apiKeyHelper`. Until the opencode input is
    # bumped from a Mac (the flake URL is file:///Users/casazza/..., so
    # luna can't update it), every darwin eval fails with
    #   error: The option `programs.opencode.telemetry' does not exist.
    # Dropping the option here keeps darwin eval green. Re-introduce it
    # (endpoint = "http://luna.local:6006") after `nix flake lock
    # --update-input opencode` on any Mac lands a rev containing
    # feat(nix): expose programs.opencode.telemetry.
    managedConfig = {
      share = "disabled";
      enabled_providers = [
        "anthropic"
        "exo"
      ];
      provider.anthropic.options.baseURL = "https://vertex-proxy.sdgr.app/v1";
      # Exo cluster: OpenAI-compatible local endpoint for Qwen3 Coder Next.
      # Reuses the same apiPort declared in local.hermes.exo.apiPort above.
      provider.exo = {
        npm = "@ai-sdk/openai-compatible";
        name = "exo";
        options = {
          baseURL = "http://127.0.0.1:${toString config.local.hermes.exo.apiPort}/v1";
          apiKey = "x";
        };
        models = {
          ${config.local.hermes.localModel} = {
            name = "Qwen3-Coder-Next-8bit";
          };
        };
      };
    };
    vertex = {
      enable = true;
      projectId = "vertex-code-454718";
      region = "us-east5";
      baseURL = "https://vertex-proxy.sdgr.app/v1";
    };
    apiKeyHelper = true;
  };

  # opencode user-level config: MCP servers for cross-conversation memory (hippo)
  # and read/write access to the Obsidian PKM vault (mcp-server-filesystem).
  #
  # NOTE: this lives in ~/.config/opencode/opencode.json rather than
  # programs.opencode.managedConfig because the Schrodinger opencode package
  # hard-codes OPENCODE_MANAGED_CONFIG_DIR in its own wrapper to its bundled
  # etc/opencode dir (nix/opencode.nix). That makes the system managed config
  # at /Library/Application Support/opencode unreachable. The user-level config
  # is loaded normally by both wrapped and unwrapped opencode binaries.
  home-manager.users.${user.name}.home.file.".config/opencode/opencode.json".source =
    (pkgs.formats.json { }).generate "opencode-user.json"
      {
        "$schema" = "https://opencode.ai/config.json";
        mcp = {
          hippo = {
            type = "local";
            command = [
              "${config.local.hermes.hippo.package}/bin/hippo-server"
              "--memory-dir"
              "/Users/${user.name}/.hippo"
            ];
            environment.HIPPO_LOG = config.local.hermes.hippo.logLevel;
            enabled = true;
          };
          obsidian-vault = {
            type = "local";
            command = [
              "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem"
              "/Users/${user.name}/Repositories/ocasazza/obsidian/vault"
            ];
            enabled = true;
          };
        };
      };

  # Enable autopkgserver for Fleet GitOps package building
  services.autopkgserver = {
    enable = true;
    # Point to git-fleet repo for recipe overrides (development machine only)
    recipeOverrideDirs = "/Users/${user.name}/Repositories/schrodinger/git-fleet/lib/software";
  };

  # Set desktop wallpaper
  # Claude Code API key helper now managed by programs.claude-code module
  system.activationScripts.postActivation.text = ''
    # Set wallpaper (timeout to avoid hanging on headless/lid-closed machines)
    timeout 5 sudo -u ${user.name} osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"' 2>/dev/null || true
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

  # ── shared JuiceFS client (talks to luna's TiKV + S3) ────────────────
  # Every Mac in the fleet mounts the shared filesystem at /Volumes/juicefs
  # so writes from any host land in luna's SeaweedFS object store.
  #
  # Off-LAN behavior: when luna.local is unreachable the launchd mount
  # daemon retries (KeepAlive=true). The mount-point exists but is empty
  # until the host is back on the home network or Tailscale (TBD).
  #
  # Secret seeding (one-time, per-Mac, out-of-band):
  #   sudo install -d -m 0700 -o root -g wheel /var/lib/juicefs-secrets
  #   echo -n 'admin' | sudo install -m 0600 /dev/stdin /var/lib/juicefs-secrets/access-key
  #   sudo install -m 0600 /dev/stdin /var/lib/juicefs-secrets/secret-key  # paste luna's seaweedfs admin secret
  #
  # macFUSE: nix-homebrew is currently disabled in this flake so the
  # cask install path is opted out via requireNixHomebrew=false. User
  # installs macFUSE once-per-Mac:
  #   brew install --cask macfuse
  # then approves the kext in System Settings → Privacy & Security and
  # reboots. The activation script prints a reminder until the kext is
  # detected at /Library/Filesystems/macfuse.fs.
  services.macfuse = {
    enable = true;
    requireNixHomebrew = false;
  };

  services.juicefs = {
    enable = true;
    mounts.shared = {
      metaUrl = "tikv://luna.local:2379/shared";
      storageType = "s3";
      bucket = "http://luna.local:8333/shared";
      mountPoint = "/Volumes/juicefs";
      accessKeyFile = "/var/lib/juicefs-secrets/access-key";
      secretKeyFile = "/var/lib/juicefs-secrets/secret-key";
      formatOnFirstBoot = false; # luna formats; clients only mount
      cacheDir = "/var/cache/juicefs/shared";
      cacheSize = 5120; # 5 GiB local read cache per Mac
    };
  };

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
      # `outer.top` matches `sketchybarHeight` (let-bound at the top of
      # this file) so tiled windows clear the bar instead of being
      # overlaid by it. The other gaps stay at 1px so the tiling itself
      # still feels tight.
      gaps = {
        inner.horizontal = 1;
        inner.vertical = 1;
        outer.left = 1;
        outer.right = 1;
        outer.top = sketchybarHeight;
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
        # Tile halves
        "ctrl-alt-left" = "move left";
        "ctrl-alt-right" = "move right";
        "ctrl-alt-up" = "move up";
        "ctrl-alt-down" = "move down";
        # Cycle windows in workspace
        "alt-backtick" =
          "focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-next";
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

  # Custom menu bar
  services.sketchybar = {
    enable = true;
    extraPackages = with pkgs; [
      jq
      aerospace
    ];
    config = ''
      # ── Colors (pastel purple palette) ─────────────────────────
      # BAR_COLOR is fully transparent so sketchybar visually merges
      # with the macOS menu bar above it. Items still have ITEM_BG so
      # they remain readable against window content. The bar itself
      # only renders a 1px bottom BORDER_COLOR line as a divider.
      BAR_COLOR=0x00000000
      BORDER_COLOR=0x40b4a7d6
      ITEM_BG=0xff313244
      ACCENT=0xffb4a7d6
      TEXT=0xffcdd6f4
      SUBTEXT=0xffa6adc8

      # ── Bar appearance ─────────────────────────────────────────
      # Height matches `sketchybarHeight` in the let-binding above; if
      # you change one, change the other (or AeroSpace's outer.top will
      # drift out of sync).
      #
      # The "bottom-border-only" trick: sketchybar only supports a
      # 4-sided border, so we use `y_offset=-1` to push the bar 1px
      # above the screen edge — the top/left/right borders fall off-
      # screen and only the bottom border remains visible as a
      # divider between the bar and tiled windows below.
      sketchybar --bar \
        height=${toString sketchybarHeight} \
        color=$BAR_COLOR \
        border_width=1 \
        border_color=$BORDER_COLOR \
        shadow=off \
        position=top \
        sticky=on \
        padding_left=6 \
        padding_right=6 \
        topmost=window \
        y_offset=-1 \
        margin=0 \
        corner_radius=0

      # ── Defaults ───────────────────────────────────────────────
      sketchybar --default \
        icon.font="JetBrainsMono Nerd Font Mono:Bold:12.0" \
        icon.color=$TEXT \
        label.font="JetBrainsMono Nerd Font Mono:Regular:11.0" \
        label.color=$TEXT \
        background.color=$ITEM_BG \
        background.corner_radius=4 \
        background.height=20 \
        background.padding_left=3 \
        background.padding_right=3 \
        padding_left=3 \
        padding_right=3

      # ── AeroSpace workspaces ───────────────────────────────────
      for sid in 1 2 3 4 5; do
        sketchybar --add item space.$sid left \
          --set space.$sid \
            associated_space=$sid \
            icon=$sid \
            icon.padding_left=10 \
            icon.padding_right=10 \
            background.color=$ITEM_BG \
            background.drawing=on \
            label.drawing=off \
            click_script="aerospace workspace $sid" \
            script='
              if [ "$SELECTED" = "true" ]; then
                sketchybar --set $NAME icon.color=0xffb4a7d6 background.color=0xff45475a
              else
                sketchybar --set $NAME icon.color=0xffa6adc8 background.color=0xff313244
              fi
            '
      done

      # ── Separator ──────────────────────────────────────────────
      sketchybar --add item separator left \
        --set separator \
          icon="│" \
          icon.color=$ACCENT \
          icon.padding_left=4 \
          label.drawing=off \
          background.drawing=off

      # ── Front app ──────────────────────────────────────────────
      sketchybar --add item front_app left \
        --set front_app \
          icon.drawing=off \
          label.color=$TEXT \
          label.font="JetBrainsMono Nerd Font Mono:Bold:13.0" \
          background.drawing=off \
          script='sketchybar --set $NAME label="$INFO"' \
        --subscribe front_app front_app_switched

      # ── Clock ──────────────────────────────────────────────────
      sketchybar --add item clock right \
        --set clock \
          update_freq=30 \
          icon="" \
          icon.color=$ACCENT \
          icon.padding_left=8 \
          label.padding_right=8 \
          background.drawing=on \
          script='sketchybar --set $NAME label="$(date "+%H:%M")"'

      # ── Date ───────────────────────────────────────────────────
      sketchybar --add item date right \
        --set date \
          update_freq=3600 \
          icon="" \
          icon.color=$ACCENT \
          icon.padding_left=8 \
          label.padding_right=8 \
          background.drawing=on \
          script='sketchybar --set $NAME label="$(date "+%a %d %b")"'

      # ── Battery ────────────────────────────────────────────────
      sketchybar --add item battery right \
        --set battery \
          update_freq=120 \
          icon.color=$ACCENT \
          icon.padding_left=8 \
          label.padding_right=8 \
          background.drawing=on \
          script='
            PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | head -1 | tr -d "%")
            CHARGING=$(pmset -g batt | grep -c "AC Power")
            if [ "$CHARGING" -gt 0 ]; then
              ICON=""
            elif [ "$PERCENTAGE" -gt 80 ]; then
              ICON=""
            elif [ "$PERCENTAGE" -gt 60 ]; then
              ICON=""
            elif [ "$PERCENTAGE" -gt 40 ]; then
              ICON=""
            elif [ "$PERCENTAGE" -gt 20 ]; then
              ICON=""
            else
              ICON=""
            fi
            sketchybar --set $NAME icon="$ICON" label="''${PERCENTAGE}%"
          '

      # ── Cheatsheet (popup of hotkeys) ──────────────────────────
      # Click the keyboard glyph in the bar to drop down a popup of
      # all AeroSpace + Ghostty + Zellij + system hotkeys. Toggle
      # idempotently with `sketchybar --set cheatsheet popup.drawing=toggle`.
      # This integrates natively with the existing bar instead of
      # adding a second widget engine (\u00dcbersicht/SwiftBar).
      sketchybar --add item cheatsheet right \
        --set cheatsheet \
          icon="" \
          icon.color=$ACCENT \
          icon.padding_left=8 \
          icon.padding_right=8 \
          label.drawing=off \
          background.drawing=on \
          click_script="sketchybar --set cheatsheet popup.drawing=toggle" \
          popup.background.color=$BAR_COLOR \
          popup.background.corner_radius=10 \
          popup.background.border_color=$ACCENT \
          popup.background.border_width=1 \
          popup.background.shadow.drawing=on \
          popup.horizontal=off \
          popup.align=right \
          popup.y_offset=4

      # Helper to add a section header row
      add_cheat_header() {
        local name="$1"
        local title="$2"
        sketchybar --add item "$name" popup.cheatsheet \
          --set "$name" \
            icon="$title" \
            icon.color=$ACCENT \
            icon.font="JetBrainsMono Nerd Font Mono:Bold:13.0" \
            icon.padding_left=12 \
            icon.padding_right=12 \
            label.drawing=off \
            background.drawing=off \
            background.padding_left=0 \
            background.padding_right=0
      }

      # Helper to add a key/description row
      add_cheat_row() {
        local name="$1"
        local key="$2"
        local desc="$3"
        sketchybar --add item "$name" popup.cheatsheet \
          --set "$name" \
            icon="$key" \
            icon.color=0xfff4bf75 \
            icon.font="JetBrainsMono Nerd Font Mono:Regular:12.0" \
            icon.padding_left=14 \
            icon.padding_right=10 \
            icon.width=180 \
            icon.align=left \
            label="$desc" \
            label.color=$TEXT \
            label.font="JetBrainsMono Nerd Font Mono:Regular:12.0" \
            label.padding_right=14 \
            background.drawing=off
      }

      # ── AeroSpace ─────────────────────────────────────────────
      add_cheat_header  cheat_aero_h     "── AeroSpace ──"
      add_cheat_row     cheat_aero_focus "alt + h/j/k/l"          "Focus left/down/up/right"
      add_cheat_row     cheat_aero_move  "alt + shift + h/j/k/l"  "Move window"
      add_cheat_row     cheat_aero_resize "alt + shift + - / ="    "Resize -50 / +50"
      add_cheat_row     cheat_aero_tiles "alt + /"                 "Layout tiles"
      add_cheat_row     cheat_aero_acc   "alt + ,"                 "Layout accordion"
      add_cheat_row     cheat_aero_full  "alt + f"                 "Fullscreen"
      add_cheat_row     cheat_aero_ws    "alt + 1..5"              "Switch workspace"
      add_cheat_row     cheat_aero_mvws  "alt + shift + 1..5"      "Move window to workspace"
      add_cheat_row     cheat_aero_arrow "ctrl + alt + arrows"     "Move window (arrow keys)"
      add_cheat_row     cheat_aero_cyc   "alt + \\\`"              "Cycle windows in workspace"
      add_cheat_row     cheat_aero_svc   "alt + shift + ;"         "Service mode"
      add_cheat_row     cheat_aero_svr   "  service: r / f / esc"  "Flatten / float / reload"

      # ── Ghostty ───────────────────────────────────────────────
      add_cheat_header  cheat_gh_h       "── Ghostty ──"
      add_cheat_row     cheat_gh_n       "cmd + n / t / w"         "Window / tab / close"
      add_cheat_row     cheat_gh_z       "cmd + +/- / 0"           "Zoom in / out / reset"
      add_cheat_row     cheat_gh_k       "cmd + k"                 "Clear screen"
      add_cheat_row     cheat_gh_split   "cmd + shift + d/e/o"     "(unbound — Zellij owns splits)"

      # ── Zellij ────────────────────────────────────────────────
      add_cheat_header  cheat_zj_h       "── Zellij ──"
      add_cheat_row     cheat_zj_pane    "alt + ] / ["             "Next / prev pane"
      add_cheat_row     cheat_zj_tab     "alt + o / i"             "Next / prev tab"
      add_cheat_row     cheat_zj_new     "alt + n"                 "New pane"
      add_cheat_row     cheat_zj_p       "ctrl + p"                "PANE mode (d/r/x/f/w/e)"
      add_cheat_row     cheat_zj_n_mode  "ctrl + n / h / t"        "Resize / move / tab modes"
      add_cheat_row     cheat_zj_s       "ctrl + s / o / g / q"    "Scroll / session / lock / quit"

      # ── System ────────────────────────────────────────────────
      add_cheat_header  cheat_sys_h      "── System ──"
      add_cheat_row     cheat_sys_caps   "caps lock"               "→ Control"
      add_cheat_row     cheat_sys_spot   "cmd + space"             "Spotlight"
      add_cheat_row     cheat_sys_tab    "cmd + tab / \\\`"        "App / window cycle"
      add_cheat_row     cheat_sys_mc     "ctrl + ↑ / ←/→"          "Mission Control / desktops"
      add_cheat_row     cheat_sys_shot   "cmd + shift + 3/4/5"     "Screenshot full/region/tools"

      # ── Force initial update ───────────────────────────────────
      sketchybar --update
    '';
  };

  # Enable SSH (Remote Login) so this machine is reachable as a remote builder
  # and discoverable via mDNS (.local) by other cluster nodes.
  services.openssh.enable = true;

  # Determinate Nix manages the daemon, nix binary, and nix.conf.
  # Don't let nix-darwin override it with a nixpkgs nix package.
  # See: https://docs.determinate.systems/getting-started/individual-install/#with-nix-darwin
  nix.enable = false;

  # System packages are auto-applied via
  # `modules/darwin/system-packages` (snowfall auto-discovery). Only
  # host-level additions go here.
  environment.systemPackages = [
    consortium.packages.${pkgs.system}.consortium-cli
  ];

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
    # Claude Code env vars now managed by programs.claude-code module
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

    # Google Cloud credentials for Vertex AI now managed by programs.claude-code module

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

        # Always show the menu bar (don't auto-hide). When the menu bar
        # auto-hides, macOS reports the full screen frame to AeroSpace
        # which then can't account for the menu bar zone, so the bar
        # pops over tiled windows on hover. Always-visible means
        # AeroSpace's `gaps.outer.top` only needs to clear sketchybar.
        _HIHideMenuBar = false;

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
          # Prevent double-click title bar from filling screen (fights AeroSpace)
          AppleActionOnDoubleClick = "None";
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
          HideDesktop = false;
          AppWindowGroupingBehavior = false;
          AutoHide = false;
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
