{
  pkgs,
  lib,
  user ? lib.salt.user,
  config,
  consortium ? null,
  ...
}:

let
  wallpaper = ../../../modules/_darwin-support/files/AFRC2017-0233-007-large.jpg;
  # Sketchybar's pixel height. AeroSpace's `gaps.outer.top` is set to
  # this same value so tiled windows start beneath the bar instead of
  # being clipped by it. Adjust here to keep both in sync.
  sketchybarHeight = 28;
  # GN9 is the dev workstation (heavy local inference, full hippo
  # obsidian sync, faster-whisper voice). The other 3 cluster Macs
  # (CK2/GJH/L75T) are kept lean for compute headroom — they route
  # local model calls through LiteLLM → pdx-nxst-003 vLLM instead.
  isWorkstation = config.networking.hostName == "GN9CFLM92K-MBP";
in
{
  imports = [
    ../../../modules/darwin/home-manager.nix
    ../../../modules/darwin/power
    ../../../modules/shared
    ../../../modules/shared/skills
    ../../../modules/shared/cachix
    ../../../modules/shared/distributed-builds
    ../../../modules/shared/hermes
    ../../../modules/shared/obsidian-vault
  ];

  # ── sops-nix (darwin) ───────────────────────────────────────────────
  # Secrets materialization at launchd activation. Each Mac's
  # /etc/ssh/ssh_host_ed25519_key is auto-used as the age identity via
  # sops.age.sshKeyPaths' default (services.openssh.enable = true below).
  #
  # TODO(sops-darwin): L75T4YHXV7-MBA's host age key is not yet in
  # .sops.yaml — until its ssh-to-age pubkey is added under
  # `&host_l75t4yhxv7_mba` and every consumer secret is re-encrypted
  # via `sops updatekeys`, sops-install-secrets will log "no key could
  # decrypt the data" on that Mac at activation. Eval still succeeds
  # — the validation is runtime-only. Consumers are written to
  # tolerate this:
  #   * fleet.env → the system.activationScripts.fleetSecrets block
  #     below guards on `if [ -f "$FLEET_SECRETS_FILE" ]`.
  #   * litellm-key-{claude-code,opencode}-darwin → the consuming
  #     wrappers guard on `[ -r FILE ]` and fall through to a clear
  #     error message if the file is missing, rather than crashing
  #     the shell.
  sops = {
    defaultSopsFile = ../../../secrets/fleet.env;
    defaultSopsFormat = "dotenv";
    # age.sshKeyPaths defaults to [ /etc/ssh/ssh_host_ed25519_key ] which
    # is exactly what we want — no override needed.
    secrets = {
      # Fleet MDM env file — whole file is the payload, consumed by the
      # fleetSecrets activation script below which copies the decrypted
      # file verbatim to ~/.fleet_secrets and sources it from zsh.
      fleet = {
        sopsFile = ../../../secrets/fleet.env;
        format = "dotenv";
      };
      # LiteLLM virtual key for claude-code. Single `litellm_api_key`
      # scalar holding a `KEY=value` line; sops-nix writes the value to
      # /run/secrets/litellm-key-claude-code-darwin. Minted by
      # pdx-nxst-003's `litellm-team-bootstrap.service` (in the
      # nixstation repo) and committed back into the sops yaml here.
      # The claude-code wrapper (modules/darwin/claude-code) reads the
      # file at invocation time and exports the value as
      # ANTHROPIC_API_KEY. opencode's keys live in
      # modules/darwin/opencode/default.nix — see the NOTE just below.
      litellm-key-claude-code-darwin = {
        sopsFile = ../../../secrets/litellm-key-claude-code-darwin.yaml;
        format = "yaml";
        key = "litellm_api_key";
        # Mode 0440 + group=staff so the user-shell sourcing the file
        # (zsh interactive) can read it; default 0400 root would block
        # opencode's per-shell load.
        mode = "0440";
        owner = "root";
        group = "staff";
      };
      # NOTE: opencode's two virtual keys (litellm-key-opencode-darwin
      # and azure-api-key-opencode-darwin) are declared in
      # modules/darwin/opencode/default.nix alongside the rest of the
      # opencode wiring. Snowfall auto-applies that module on every
      # darwin host.
      # LiteLLM virtual key for hermes (service account: local-svc-hermes,
      # local-compute team). Hermes' shellInit reads the file at every
      # shell start and exports `LITELLM_HERMES_API_KEY`, which hermes'
      # config.yaml references via `api_key: env:LITELLM_HERMES_API_KEY`.
      # Without this, hermes' /v1 path against LiteLLM 401s and the only
      # working route is the /vertex/v1 cloud passthrough (gcloud id-token).
      #
      # Mode 0440 + group=staff so the user shell that sources the
      # file (zsh interactive) can read it; default 0400 root would block it.
      # Re-encrypted for each darwin host_* age key listed in `.sops.yaml`'s
      # litellm-key-local-svc-hermes rule.
      litellm-key-local-svc-hermes = {
        sopsFile = ../../../secrets/litellm-key-local-svc-hermes.yaml;
        format = "yaml";
        key = "litellm_api_key";
        mode = "0440";
        owner = "root";
        group = "staff";
      };
      # Gemini Enterprise API key for hermes' gemini provider fallback.
      # When mainModel.geminiKeyFile is set, the hermes activation script
      # replaces `$GEMINI_API_KEY` in config.yaml with this value.
      #
      # To enable: encrypt the secret first, then uncomment this block:
      #   sops encrypt --in-place secrets/gemini-enterprise-api-key.yaml
      #   sops updatekeys secrets/gemini-enterprise-api-key.yaml
      #   git add secrets/gemini-enterprise-api-key.yaml
      #
      # gemini-enterprise-api-key = {
      #   sopsFile = ../../../secrets/gemini-enterprise-api-key.yaml;
      #   format = "yaml";
      #   key = "gemini_api_key";
      #   mode = "0440";
      #   owner = "root";
      #   group = "staff";
      # };
      # Redis password for pdx-nxst-003's JuiceFS metadata KV. Sops-nix writes
      # just the value to /run/secrets/redis-seaweedfs-password.
      # Re-encrypted to every host_*  age key in `.sops.yaml` so each
      # Mac surfaces it at activation. See `nixos-config/todo.md`
      # Stage 0.9.
      redis-seaweedfs-password = {
        sopsFile = ../../../secrets/redis-seaweedfs-password.yaml;
        format = "yaml";
        key = "redis_seaweedfs_password";
      };
      # SeaweedFS S3 admin secret. Same key group as redis above. The
      # juicefs mount script reads this as `--secret-key <value>` so
      # the per-Mac S3 client auths against pdx-nxst-003's S3 gateway. Without
      # this, the operator had to manually `cp /var/lib/seaweedfs/...`
      # onto each Mac (recorded in earlier doc comments below).
      seaweedfs-admin-secret = {
        sopsFile = ../../../secrets/seaweedfs-admin-secret.yaml;
        format = "yaml";
        key = "seaweedfs_admin_secret";
      };
    };
  };

  local.obsidianVault = {
    enable = true;
    vaultPath = "/Users/${user.name}/Repositories/ocasazza/obsidian/vault";
    reingestAuto.enable = true;
  };

  # Mac-side OTel collector daemon. Pushes hostmetrics + opencode
  # pipeline logs + reingest gauges to pdx-nxst-003's OTLP intake at
  # pdx-nxst-003:4317. Replaces the old "Macs send nothing" gap that
  # left the Grafana reingest tiles empty. See modules/darwin/observability.
  local.darwinObservability.enable = true;

  # Workstation-only daemons (the dev-only stuff, NOT the cluster):
  #   * oMLX        — single-node MLX server feeding opencode's omlx
  #                   provider; redundant on cluster nodes that already
  #                   federate through exo + LiteLLM.
  #   * voice       — faster-whisper model; only the workstation has the
  #                   mic+keyboard interactive loop.
  #
  # exo IS the cluster — it has to run on every TB-meshed node
  # (CK2 ↔ GJH ↔ L75T) for distributed inference to work, and freeing
  # RAM on those nodes (consumer apps, oMLX, etc.) is precisely what
  # makes more of it available to the exo MLX shard. Don't gate exo
  # on workstation. GN9 has no TB cables and is excluded from the mesh
  # by topology, so its `exo.enable = true` is a no-op there.

  local.hermes = {
    enable = true;
    voice.enable = isWorkstation; # faster-whisper model is large

    # ── Provider configuration ──────────────────────────────────────────
    # Hermes' built-in provider registry handles auth automatically for
    # most providers (OAuth ADC for gemini, env-var resolution for
    # anthropic, etc.). For providers not in the registry, set baseURL
    # + apiKey directly — hermes treats it as a custom OpenAI-compatible
    # endpoint.
    #
    # Built-in providers: gemini, anthropic, openai-codex, copilot, zai,
    # kimi-coding, minimax, deepseek, alibaba, ai-gateway, opencode-zen,
    # opencode-go, hf, nous.
    #
    # --- Azure OpenAI (delegation) ---
    # delegation.baseURL = "https://<resource>.openai.azure.com/openai/deployments/<deployment>";
    # delegation.apiKey = "$AZURE_API_KEY";
    # delegation.azureKeyFile = config.sops.secrets.azure-api-key-opencode-darwin.path;
    #
    # --- Vertex Proxy (Claude via Schrodinger proxy) ---
    # mainModel.provider = null;
    # mainModel.baseURL = "https://vertex-proxy.sdgr.app/v1";
    # mainModel.apiKey = "$VERTEX_PROXY_ID_TOKEN";
    # mainModel.vertexProxyIdToken = true;  # activation script calls gcloud auth print-identity-token
    #
    # --- Gemini Enterprise (Vertex AI) ---
    # mainModel.provider = null;
    # mainModel.baseURL = "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/gemini-enterprise-495018/locations/us-central1/endpoints/openapi";
    # mainModel.apiKey = "$GEMINI_API_KEY";  # or use ADC OAuth
    # mainModel.geminiKeyFile = config.sops.secrets.gemini-enterprise-api-key.path;

    mainModel = {
      name = "glm-5.1-fp8";
      baseURL = "https://glm-5-1-fp8.autoscale.sdgr.app/v1";
      apiKey = "noauth";
    };

    # Vertex AI Claude models via LiteLLM passthrough.
    # Switch at runtime: /model custom:vertex-proxy:claude-opus-4-7
    vertexProxy.enable = true;

    # Plan Execution: Azure OpenAI (Kimi K2.6) via direct endpoint
    delegation = {
      enable = true;
      model = "Kimi-K2.6";
      baseURL = "https://schrodinger-code.openai.azure.com/openai/deployments/Kimi-K2.6";
      apiKey = "$AZURE_API_KEY";
      azureKeyFile = config.sops.secrets.azure-api-key-opencode-darwin.path;
      models = {
        "Kimi-K2.6" = {
          contextLength = 131072;
        };
      };
    };

    # Aux tasks: Gemini via built-in provider (vision + web_extract)
    auxiliary = {
      enable = true;
      provider = "gemini";
      model = "gemini-2.5-pro";
    };

    extraSkillsDir = config.local.skills.path;

    # Compression: trigger early for high-context models.
    compression.threshold = "0.10";
    compression.summaryModel = "litellm/qwen3.6-35b-a3b";

    # Wire the per-host LiteLLM virtual key. With this set, hermes'
    # local-routing path (explicit model aliases / embedding) authenticates
    # against pdx-nxst-003:4000/v1 and unlocks the rest of the GPU pool
    # fronted by LiteLLM. Without it, only /vertex/v1 (gcloud id-token,
    # no virtual key) is reachable.
    # Use the Caddy proxy endpoint (:8080/litellm) so no local SSH tunnel
    # is required.
    #
    # Direct to LiteLLM
    litellm.endpoint = lib.salt.ai.providers.litellm.caddyEndpoint;
    litellm.virtualKeyFile = config.sops.secrets.litellm-key-opencode-darwin.path;
    litellm.models = {
      "qwen3.6-35b-a3b" = {
        contextLength = 131072;
      };
      "qwen3-coder-next" = {
        contextLength = 131072;
      };
    };

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
      - AI stack: hermes-agent (Schrodinger fork), opencode (stock pkgs.opencode from
        nixpkgs; user-level config in modules/darwin/opencode), claude-code — all routed
        through Vertex AI proxy at https://vertex-proxy.sdgr.app or pdx-nxst-003's LiteLLM
        proxy at :4000. Auth via `gcloud auth print-identity-token` written to `~/.hermes/.env`.
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
        Edit secrets with `sops secrets/fleet.env` or any `secrets/*.yaml` file.
      - Private flake inputs (git-fleet, git-fleet-runner, hermes) require SSH agent
        with `~/.ssh/id_ed25519` loaded.

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

    # Memory limits: increase for larger context models
    memoryCharLimit = 8192;
    userCharLimit = 4096;

    skin = "schrodinger";
  };

  # oMLX local inference server with continuous batching & tiered KV cache.
  # Models download to ~/.omlx/models; the SSD cache lives at ~/.omlx/cache.
  # Serves an OpenAI-compatible API on localhost:8000/v1 used by opencode's
  # omlx provider and the oc-voice pipeline.
  #
  # Workstation-only: oMLX loads a Qwen3-Coder MLX model (~16 GiB) into
  # RAM at boot. Non-workstation cluster Macs route through LiteLLM →
  # pdx-nxst-003 vLLM instead; no local MLX server needed.
  local.omlx = {
    enable = isWorkstation;
    port = 8000;
    ssdCacheDir = "/Users/${user.name}/.omlx/cache";
    maxConcurrentRequests = 8;
  };

  # Claude Code direct to vertex-proxy. Identical across every darwin
  # host in this fleet, so the per-host files at
  # systems/aarch64-darwin/<host>/default.nix only need to override
  # what's actually host-specific (hostname, exo peers, distributed-
  # builds toggle).
  #
  # We tried routing through pdx-nxst-003's LiteLLM (both /v1 router with
  # virtual keys and /vertex/v1 passthrough) for Phoenix attribution.
  # Both paths are blocked:
  #   * Router /v1 + virtual key: the coder-cloud-claude deployment
  #     uses `api_key = "forwarded-per-request"`, which forwards the
  #     LiteLLM virtual key to vertex-proxy as Authorization. vertex-
  #     proxy expects a real gcloud id-token, so 403s.
  #   * Passthrough /vertex/v1 + gcloud id-token: LiteLLM enforces
  #     virtual-key auth on every route by default, including
  #     passthroughs. The `public_routes` config flag that would let
  #     us skip auth on /vertex/* is a LiteLLM Enterprise feature.
  #
  # So claude-code talks straight to vertex-proxy with a gcloud
  # id-token from apiKeyHelper. We lose Phoenix attribution for
  # cloud-claude calls (acceptable). Local model aliases (explicit
  # host-model names, embedding) still route through pdx-nxst-003's
  # ── Unified AI Infrastructure ──────────────────────────────────────
  local.ai = {
    enable = true;
    providers = {
      litellm = {
        enable = true;
        apiKeyFile = config.sops.secrets.litellm-key-opencode-darwin.path;
      };
      vertex.enable = true;
      gemini.enable = true;
      azure = {
        enable = true;
        apiKeyFile = config.sops.secrets.azure-api-key-opencode-darwin.path;
      };
    };
  };

  # /v1 with per-host virtual keys and DO get per-key attribution, but
  # neither claude-code nor opencode calls those today \u2014
  # they're consumed by hermes / ingest / open-webui instead.
  programs.claude-code = {
    enable = true;
    model = "claude-sonnet-4-6";
    environment.MAX_THINKING_TOKENS = "10240";
    vertex = {
      enable = true;
      projectId = lib.salt.ai.providers.vertex.projectId;
      region = lib.salt.ai.providers.vertex.region;
      baseURL = lib.salt.ai.providers.vertex.proxyEndpoint;
    };
    apiKeyHelper = true;
    telemetry.enable = false;
  };

  # Pi Coding Agent — TS-based terminal harness. npm-installed; routes
  # through LiteLLM. Skills from nason-skills.
  programs.pi.enable = true;

  # Gemini CLI with personal sign-in access. extraSettings restores
  # custom seatbelt sandbox + UI verbosity that was previously hand-edited
  # in ~/.gemini/settings.json before the Nix module owned the file.
  programs.gemini-cli = {
    enable = true;
    authType = "oauth-personal";
    # Even with OAuth, configure vertex project for enterprise access
    vertex = {
      projectId = "gemini-enterprise-495018";
      region = "us-central1";
    };
    extraSettings = {
      ui.errorVerbosity = "full";
      tools = {
        sandbox = "/Users/${user.name}/Repositories/schrodinger/nixstation/.gemini/sandbox-macos-custom.sb";
        sandboxAllowedPaths = [ "/Users/${user.name}/.config/nixos-config" ];
      };
      seatbeltProfile = "custom";
      ide.hasSeenNudge = true;
      telemetry = {
        enabled = true;
        target = "local";
        logPrompts = true;
      };
      experimental = {
        autoMemory = true;
        gemma = true;
        voiceMode = true;
        worktrees = true;
        modelSteering = true;
        directWebFetch = true;
        gemmaModelRouter = {
          enabled = true;
          autoStartServer = true;
        };
        contextManagement = true;
        generalistProfile = true;
      };
    };
  };

  # opencode wiring (binary, sops keys, user-level config, MCP servers)
  # lives in modules/darwin/opencode/default.nix. Snowfall auto-applies
  # it on every darwin host.

  # Forward SSH tunnel from this Mac → pdx-nxst-003:4000 (LiteLLM).
  # AppGate SDP only forwards :22, so opencode (and anything else
  # talking to the LiteLLM federator) needs an SSH-tunneled path to
  # reach :4000 from off-LAN. autossh + launchd.user.agents keeps the
  # tunnel up across AppGate flaps and reboots; opencode's baseURL
  # points at http://localhost:4000/v1 (see modules/darwin/opencode).
  #
  # Per-user agent (not a system daemon) because:
  #   - The remote end is `casazza@pdx-nxst-003` (regular login user),
  #     so it uses ~/.ssh/id_ed25519 and ~/.ssh/known_hosts directly.
  #   - Local bind 127.0.0.1:4000 is per-user state anyway.
  #

  services.autopkgserver = {
    enable = true;
    # Point to git-fleet repo for recipe overrides (development machine only)
    recipeOverrideDirs = "/Users/${user.name}/Repositories/schrodinger/git-fleet/lib/software";
  };

  # Set desktop wallpaper + load fleet MDM secrets.
  # Both run via postActivation because nix-darwin only invokes a fixed
  # set of activation-script slots (preActivation / extraActivation /
  # postActivation). A custom `fleetSecrets` slot builds fine but is
  # never called.
  system.activationScripts.postActivation.text = ''
    # Set wallpaper (timeout to avoid hanging on headless/lid-closed machines)
    timeout 5 sudo -u ${user.name} osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"' 2>/dev/null || true

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

  # ── shared JuiceFS client (talks to pdx-nxst-003's Redis + S3) ──────
  # Every Mac in the fleet mounts the shared filesystem at /Volumes/juicefs
  # so writes from any host land in pdx-nxst-003's SeaweedFS object store.
  #
  # Off-LAN behavior: when pdx-nxst-003 is unreachable the launchd
  # mount daemon retries (KeepAlive=true). The mount-point exists but
  # is empty until the host is back on the corp network.
  #
  # Secret seeding (one-time, per-Mac, out-of-band).
  # `install` on macOS rejects /dev/stdin as source; use tee + chmod:
  #   sudo install -d -m 0700 -o root -g wheel /var/lib/juicefs-secrets
  #   echo -n 'admin' | sudo tee /var/lib/juicefs-secrets/access-key >/dev/null && sudo chmod 600 /var/lib/juicefs-secrets/access-key
  #   sudo tee /var/lib/juicefs-secrets/secret-key >/dev/null && sudo chmod 600 /var/lib/juicefs-secrets/secret-key  # paste pdx-nxst-003's seaweedfs admin secret (/var/lib/seaweedfs/admin-secret on the server)
  #   sudo tee /var/lib/juicefs-secrets/meta-password >/dev/null && sudo chmod 600 /var/lib/juicefs-secrets/meta-password  # paste pdx-nxst-003's redis-seaweedfs password (sops decrypts to /run/secrets/redis-seaweedfs-password on the server)
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
      # Migrated from `tikv://pdx-nxst-003:2379/shared` when the
      # JuiceFS metadata backend flipped to Redis (TiKV 8.5.0 didn't
      # build under gcc 15 / cmake 4.1, see the nixstation config).
      # pdx-nxst-003's redis is now bound on 6379 with mandatory auth
      # — keep this URL credential-free; metaPasswordFile injects it
      # as META_PASSWORD.
      metaUrl = "redis://pdx-nxst-001.schrodinger.com:6379/0";
      # sops-nix surfaces the redis password at /run/secrets/...; the
      # /var/lib/juicefs-secrets/meta-password manual-seed path is no
      # longer needed.
      metaPasswordFile = config.sops.secrets.redis-seaweedfs-password.path;
      storageType = "s3";
      bucket = "http://pdx-nxst-001.schrodinger.com:8333/shared";
      mountPoint = "/Volumes/juicefs";
      # accessKey is the literal string "admin" — bake it as a
      # /nix/store text file so the upstream mount script (which only
      # accepts a *file* path, not a literal value) can read it
      # without manual seeding under /var/lib/juicefs-secrets/.
      accessKeyFile = pkgs.writeText "juicefs-access-key" "admin";
      # secretKey is the SeaweedFS S3 admin secret, decrypted by sops-nix
      # at activation. See sops.secrets.seaweedfs-admin-secret above.
      secretKeyFile = config.sops.secrets.seaweedfs-admin-secret.path;
      formatOnFirstBoot = false; # pdx-nxst-003 formats; clients only mount
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
      # `topmost=window` places sketchybar above all windows but below
      # the native macOS menu bar. The bar sits directly below the
      # menu bar with no vertical offset (`y_offset=0` is the default).
      # Combined with `border_width=1` and a transparent `color`, only
      # the bottom border is visible as a subtle divider between the
      # bar and the tiled windows below.
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
  #
  # The router-routed sibling opencode binary was removed when we
  # discovered LiteLLM's free tier doesn't support `public_routes`,
  # so the /vertex/v1 passthrough requires a virtual key, but
  # virtual keys can't carry the gcloud id-token vertex-proxy needs.
  # The regular `opencode` binary (vertex-direct) is the supported
  # path for cloud claude.
  environment.systemPackages = lib.optionals (consortium != null) [
    consortium.packages.${pkgs.stdenv.hostPlatform.system}.consortium-cli
  ];

  # Set system-wide environment variables
  environment.variables = {
    # NH Darwin flake configuration — use the hostname-specific config
    # which includes exo cluster membership and all Schrodinger overrides
    NH_DARWIN_FLAKE = ".#darwinConfigurations.${config.networking.hostName}";
    # SOPS key file location
    SOPS_AGE_KEY_FILE = "/Users/${user.name}/.config/sops/age/keys.txt";
    # Gemini CLI surface
    GEMINI_CLI_SURFACE = "olive-casazza-gemini-cli";
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
