{
  config,
  lib,
  pkgs,
  user,
  hermes,
  system,
  ...
}:

with lib;

let
  cfg = config.local.hermes;

  # The effective local base_url: LiteLLM's router takes priority over
  # exo takes priority over ollama when all are configured.
  localBaseUrl =
    if cfg.litellm.enable then
      "${cfg.litellm.endpoint}/v1"
    else
      throw "No LiteLLM endpoint provided. Check hermes module paramaters";

  # api_key injected into hermes' generated config. LiteLLM's router
  # expects the virtual-key bearer; everything else keeps the legacy
  # "ollama" literal (vLLM ignores the value).
  # `$LITELLM_HERMES_API_KEY` (not `env:...`) is the literal placeholder
  # the activation-time sed replaces with the real sops-decrypted key
  # before hermes ever reads the file. Keeping a single placeholder form
  # keeps the substitution unambiguous.
  localApiKey =
    if cfg.litellm.enable then
      "$LITELLM_HERMES_API_KEY"
    else
      throw "No LiteLLM API key provided. Please provide a sops encrypted API_KEY";

  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];

  # On Darwin, rebuild hermes venv from the fork source.
  # The fork (~/Repositories/schrodinger/hermes-agent, schrodinger branch) carries
  # all Schrodinger changes as proper commits — no patches needed here.
  #
  # Two wheel overrides are still required because uv.lock doesn't include
  # macOS ARM64 variants for these packages:
  #   - onnxruntime: missing macosx_14_0_arm64 wheel
  #   - cffi: 2.0.0 regresses callback thread-safety on macOS (segfault in
  #     CoreAudio callback); pinned to 1.17.1
  hermesVenvDarwin = pkgs.callPackage (
    {
      python311,
      lib,
      callPackage,
    }:
    let
      workspace = hermes.inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = hermes.outPath;
      };
      projectOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      onnxruntimeOverlay = _final: prev: {
        onnxruntime = prev.onnxruntime.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/60/69/6c40720201012c6af9aa7d4ecdd620e521bd806dc6269d636fdd5c5aeebe/onnxruntime-1.24.4-cp311-cp311-macosx_14_0_arm64.whl";
            hash = "sha256-C9/Ojppkl87FhKq0B7cb9pfaxeG3t5dK3FC/dTO9s6I=";
          };
        });
      };
      cffiOverlay = _final: prev: {
        cffi = prev.cffi.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/6c/f5/6c3a8efe5f503175aaddcbea6ad0d2c96dad6f5abb205750d1b3df44ef29/cffi-1.17.1-cp311-cp311-macosx_11_0_arm64.whl";
            hash = "sha256-MMXgy1rkk8BMi0KRblLKOAefGyNcL4rl9FJ7ljxAHK8=";
          };
        });
      };
      pythonSet =
        (callPackage hermes.inputs.pyproject-nix.build.packages {
          python = python311;
        }).overrideScope
          (
            lib.composeManyExtensions [
              hermes.inputs.pyproject-build-systems.overlays.default
              projectOverlay
              onnxruntimeOverlay
              cffiOverlay
            ]
          );
    in
    pythonSet.mkVirtualEnv "hermes-agent-env" {
      hermes-agent = [ "all" ];
    }
  ) { };

  # Repackage hermes from the Schrodinger fork with the rebuilt venv on Darwin.
  # pname includes -schrodinger for FleetDM build identification (ITHELP-46694).
  hermesPackageDarwin =
    let
      skillsSrc = "${hermes.outPath}/skills";
      # Runtime tools — base + skill-dependent
      runtimeDeps =
        with pkgs;
        [
          nodejs_20
          ripgrep
          git
          openssh
          ffmpeg
          jq
          curl
        ]
        ++ lib.optionals (builtins.elem "github" cfg.skills) [ gh ];
      runtimePath = lib.makeBinPath runtimeDeps;
    in
    pkgs.stdenv.mkDerivation {
      pname = "hermes-agent-schrodinger";
      version = "0.1.0";
      dontUnpack = true;
      dontBuild = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hermes-agent/skills $out/bin
        # Copy only the enabled skill categories from upstream
        # TODO: Copy any skill that exists in an explicitly defined skill list
      ''
      + lib.concatMapStringsSep "\n" (cat: ''
        if [ -d "${skillsSrc}/${cat}" ]; then
          cp -r "${skillsSrc}/${cat}" "$out/share/hermes-agent/skills/${cat}"
        fi
      '') cfg.skills
      + lib.optionalString (cfg.extraSkillsDir != null) ''

        # Merge extra custom skills into the skills dir
        for dir in ${cfg.extraSkillsDir}/*/; do
          cat_name="$(basename "$dir")"
          if [ ! -d "$out/share/hermes-agent/skills/$cat_name" ]; then
            cp -r "$dir" "$out/share/hermes-agent/skills/$cat_name"
          else
            # Merge individual skills into existing category
            cp -rn "$dir"/* "$out/share/hermes-agent/skills/$cat_name/" 2>/dev/null || true
          fi
        done
      ''
      + ''

        ${lib.concatMapStringsSep "\n"
          (name: ''
            makeWrapper ${hermesVenvDarwin}/bin/${name} $out/bin/${name} \
              --suffix PATH : "${runtimePath}" \
              --set HERMES_BUNDLED_SKILLS $out/share/hermes-agent/skills
          '')
          [
            "hermes"
            "hermes-agent"
            "hermes-acp"
          ]
        }
        runHook postInstall
      '';
      meta = with lib; {
        description = "AI agent with advanced tool-calling capabilities";
        homepage = "https://github.com/NousResearch/hermes-agent";
        mainProgram = "hermes";
        license = licenses.mit;
        platforms = platforms.unix;
      };
    };

  defaultPackage = if isDarwin then hermesPackageDarwin else hermes.packages.${system}.default;
in
{
  options.local.hermes = {
    enable = mkEnableOption "Hermes Agent TUI";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      description = "The Hermes Agent package to install";
    };

    skills = mkOption {
      type = types.listOf types.str;
      default = [
        "software-development"
        "autonomous-ai-agents"
        "github"
        "research"
        "productivity"
        "mcp"
        "note-taking"
      ];
      description = "Skill categories to include from upstream hermes bundled skills";
    };

    extraSkillsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a directory of additional custom skills.
        These are merged alongside the upstream bundled skills.
      '';
    };

    vertexProxy = {
      baseURL = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.vertex.proxyBaseURL;
        description = ''
          Vertex AI proxy base URL (Anthropic SDK appends /v1/messages).
          When `local.hermes.litellm.enable = true` this value is
          ignored — cloud calls route through LiteLLM's `/vertex/v1`
          passthrough instead.
        '';
      };

      model = mkOption {
        type = types.str;
        default = lib.salt.ai.models.claudeSonnet;
        description = "Model to use via Vertex proxy";
      };
    };

    # ── LiteLLM-routed path ───────────────────────────────────────────
    # Route all hermes calls through the LiteLLM proxy on desk-nxst-001:
    #   - `vertexProxy.baseURL` references become `<endpoint>/vertex/v1`
    #     (passthrough — gcloud id-token still flows via the refresh_token
    #     shim into ~/.hermes/.env)
    #   - `localBaseUrl` (ollama/exo) becomes `<endpoint>/v1` with
    #     authentication via the sops-decrypted virtual key
    #
    # Mutually exclusive with the legacy path: `enable = true` on this
    # block overrides everything that would otherwise hit vertex-proxy
    # or localhost:52416 directly.
    litellm = {
      # Default-on: hermes routes through LiteLLM rather than hitting Vertex /
      # exo directly. The legacy direct path is still reachable by setting
      # `local.hermes.litellm.enable = false;`. When enabled but no
      # `virtualKeyFile` is wired, only the cloud passthrough (/vertex/v1)
      # works — local routing (/v1) needs the per-host sops-decrypted key.
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route Hermes through LiteLLM instead of direct providers";
      };

      endpoint = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.caddyEndpoint;
        description = ''
          LiteLLM base URL. Serves `/vertex/v1` (passthrough for cloud
          Claude) and `/v1` (OpenAI-compat router for local groups).

          Defaults to the Caddy-fronted FQDN path
          (`http://desk-nxst-001.schrodinger.com:8080/litellm`) so every
          fleet client routes through one auditable reverse proxy that
          aggregates the various upstream providers. Bare `:4000` is
          reachable inside the corp LAN but bypasses Caddy.
        '';
      };

      virtualKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to this client's LiteLLM virtual key file. Expected
          format: a single `LITELLM_HERMES_API_KEY=sk-...` line that
          the zsh shellInit sources at every new shell, so the value
          is exported as `$LITELLM_HERMES_API_KEY` for hermes' config
          file to pick up via its `env:LITELLM_HERMES_API_KEY` indirect
          reference.

          On desk-nxst-001 this is
          `config.sops.secrets.litellm-key-hermes.path`; on darwin
          it's the /run/secrets path once sops-nix is wired on darwin
          hosts.
        '';
      };

      defaultLocalGroup = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.defaultLocalGroup;
        description = ''
          LiteLLM model alias hermes refers to when picking a
          "local" model (delegation in non-vertex mode, auxiliary
          in non-vertex mode). Defaults to desk-nxst-001-qwen3.6-35b-a3b.
        '';
      };
    };

    delegation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route subtasks to a dedicated subagent model";
      };

      model = mkOption {
        type = types.str;
        default = "claude-haiku-4-5";
        description = "Model to use for subagent delegation";
      };

      provider = mkOption {
        type = types.str;
        default = "anthropic";
        description = "Provider for subagent delegation (anthropic uses the Vertex proxy)";
      };

      useVertexProxy = mkOption {
        type = types.bool;
        default = true;
        description = "Route subagent delegation through the Vertex AI proxy (uses vertexProxy.baseURL)";
      };

      maxIterations = mkOption {
        type = types.int;
        default = 50;
        description = "Per-subagent iteration cap";
      };

      defaultToolsets = mkOption {
        type = types.listOf types.str;
        default = [
          "terminal"
          "file"
          "web"
        ];
        description = "Default toolsets available to subagents";
      };
    };

    auxiliary = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auxiliary model configuration for side tasks";
      };

      useVertexProxy = mkOption {
        type = types.bool;
        default = true;
        description = "Route auxiliary tasks (vision, web_extract, approval, etc.) through Vertex proxy with Haiku instead of local LLM";
      };

      model = mkOption {
        type = types.str;
        default = "claude-haiku-4-5";
        description = "Model for auxiliary tasks when useVertexProxy is true";
      };
    };

    agent = {
      maxTurns = mkOption {
        type = types.int;
        default = 90;
        description = "Maximum tool-calling iterations per conversation";
      };

      reasoningEffort = mkOption {
        type = types.str;
        default = "";
        description = "Reasoning effort level: empty (medium), xhigh, high, medium, low, minimal, none";
      };

      gatewayTimeout = mkOption {
        type = types.int;
        default = 1800;
        description = "Gateway agent inactivity timeout in seconds (0 = unlimited)";
      };
    };

    compression = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic context compression when nearing model context limit";
      };

      threshold = mkOption {
        type = types.str;
        default = "0.70";
        description = "Compress when prompt tokens reach this ratio of the model context window";
      };

      protectLastN = mkOption {
        type = types.int;
        default = 20;
        description = "Always keep at least this many recent messages uncompressed";
      };

      summaryModel = mkOption {
        type = types.str;
        # Use a fast local model for compression. Must be in the LiteLLM
        # allowlist for the hermes virtual key.
        default = "litellm/desk-nxst-001-qwen3.6-35b-a3b";
        description = "Model used for compression summarisation (should be fast/cheap). Use a local model to avoid cloud egress.";
      };
    };

    display = {
      streaming = mkOption {
        type = types.bool;
        default = true;
        description = "Stream tokens to the terminal as they arrive";
      };

      showCost = mkOption {
        type = types.bool;
        default = true;
        description = "Show estimated cost in the CLI status bar";
      };

      bellOnComplete = mkOption {
        type = types.bool;
        default = true;
        description = "Play terminal bell when the agent finishes a task";
      };

      showReasoning = mkOption {
        type = types.bool;
        default = false;
        description = "Show model reasoning/thinking blocks above each response";
      };

      toolProgress = mkOption {
        type = types.enum [
          "off"
          "new"
          "all"
          "verbose"
        ];
        default = "all";
        description = "Tool call progress verbosity: off, new, all, verbose";
      };
    };

    approvals = {
      mode = mkOption {
        type = types.enum [
          "manual"
          "smart"
          "off"
        ];
        default = "smart";
        description = "Dangerous command approval mode: manual, smart (auto-approve low-risk), off";
      };
    };

    fileReadMaxChars = mkOption {
      type = types.int;
      default = 200000;
      description = "Maximum characters per read_file call — increase for large-context models like Claude";
    };

    memoryCharLimit = mkOption {
      type = types.int;
      default = 2200;
      description = "Maximum characters per memory entry";
    };

    userCharLimit = mkOption {
      type = types.int;
      default = 1375;
      description = "Maximum characters per user profile entry";
    };

    soulMd = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Content for ~/.hermes/SOUL.md — global agent identity injected into every session
        regardless of working directory (slot #1 in system prompt, before project context).
        Leave empty to keep the built-in Hermes default.
      '';
    };

    skin = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hermes display skin name (e.g. "schrodinger", "cyberpunk", "ares").
        Skins are YAML files placed at ~/.hermes/skins/<name>.yaml.
        Leave null to use the default skin.
      '';
    };

    voice = {
      enable = mkEnableOption "Hermes CLI voice mode (microphone input + TTS output)";

      recordKey = mkOption {
        type = types.str;
        default = "ctrl+b";
        description = "Key binding to start/stop voice recording in the TUI";
      };

      autoTts = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically enable TTS when voice mode starts";
      };

      silenceThreshold = mkOption {
        type = types.int;
        default = 200;
        description = "RMS level (0-32767) below which audio counts as silence";
      };

      silenceDuration = mkOption {
        type = types.float;
        default = 3.0;
        description = "Seconds of silence before recording auto-stops";
      };

      sttProvider = mkOption {
        type = types.enum [
          "local"
          "groq"
          "openai"
        ];
        default = "local";
        description = "Speech-to-text provider. 'local' uses faster-whisper with no API key";
      };

      sttModel = mkOption {
        type = types.str;
        default = "base";
        description = "Whisper model for local STT (tiny, base, small, medium, large-v3)";
      };

      ttsProvider = mkOption {
        type = types.enum [
          "edge"
          "elevenlabs"
          "openai"
          "neutts"
        ];
        default = "edge";
        description = "Text-to-speech provider. 'edge' is free with no API key";
      };

      ttsVoice = mkOption {
        type = types.str;
        default = "en-US-AriaNeural";
        description = "Voice name for Edge TTS (ignored for other providers)";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Common config: package, config file, shell init
    {
      environment.systemPackages = [ cfg.package ];

      # `force = true`: at activation, the home.activation.hermesConfigInjectKey
      # script (defined below) replaces this symlink with a real, key-injected
      # file. On the next activation HM would normally try to back up the
      # real file to `.bak` before placing a fresh symlink — and barf if the
      # `.bak` from the prior activation is still around. Force-overwrite
      # skips both the backup and the collision.
      home-manager.users.${user.name}.home.file.".hermes/config.yaml" = {
        force = true;
        text = concatStringsSep "\n" (
          (
            if cfg.litellm.enable then
              [
                "# Main model: Qwen3.6-35B-A3B-AWQ on desk-nxst-001 vLLM (always-on)."
                "# To switch models, use `/model litellm/<name>` with any alias"
                "# in the custom_providers list below."
                "model:"
                "  default: \"desk-nxst-001-qwen3.6-35b-a3b\""
                "  provider: \"litellm\""
                "  base_url: \"${cfg.litellm.endpoint}/v1\""
                "  api_key: \"$LITELLM_HERMES_API_KEY\""
                ""
              ]
            else
              [
                "# Main model: cloud Claude direct to vertex-proxy (legacy path,"
                "# active because local.hermes.litellm.enable = false)"
                "model:"
                "  default: \"${cfg.vertexProxy.model}\""
                "  provider: \"anthropic\""
                "  base_url: \"${vertexProxyBaseUrl}\""
                ""
              ]
          )
          ++ [
            "# Custom OpenAI-compatible providers — pick any of these via"
            "# `/model <provider>/<model>` in the hermes TUI. The main `model:`"
            "# block above selects the default."
            "custom_providers:"
          ]
          ++ optionals cfg.litellm.enable [
            "  # LiteLLM router on desk-nxst-001:4000. Model names must match"
            "  # the allowlist configured on the LiteLLM proxy for the hermes"
            "  # virtual key — any name not in that allowlist returns 403."
            "  - name: \"litellm\""
            "    base_url: \"${cfg.litellm.endpoint}/v1\""
            "    api_key: \"$LITELLM_HERMES_API_KEY\""
            "    models:"
            "      - \"desk-nxst-001-qwen3.6-35b-a3b\""
            "      - \"desk-nxst-004-qwen3-32b\""
            "      - \"gfr-osx26-02-qwen3-coder-next\""
            "      - \"gfr-osx26-03-qwen3-coder-next\""
            "      - \"laptop-qwen3-coder\""
            "      - \"gfr-osx26-02-gpt-oss-120b\""
            "      - \"gfr-osx26-03-gpt-oss-120b\""
            "      - \"desk-nxst-004-qwen3-embedding\""
            "      - \"pdx-nxst-001-qwen3-32b\""
            "      - \"pdx-nxst-002-qwen3-32b\""
            "      - \"pdx-nxst-002-qwen3-embedding\""
          ]
          ++ optionals cfg.delegation.enable ([
            "# Subagent delegation: local LLM (LiteLLM router when enabled)"
            "delegation:"
            "  base_url: \"${localBaseUrl}\""
            "  model: \"${cfg.delegation.model}\""
            "  api_key: \"${localApiKey}\""
            "  max_iterations: ${toString cfg.delegation.maxIterations}"
            "  default_toolsets: [${
                concatStringsSep ", " (map (t: "\"${t}\"") cfg.delegation.defaultToolsets)
              }]"
            ""
          ])
          ++ optionals cfg.auxiliary.enable ([
            "# Auxiliary tasks: local LLM (LiteLLM router when enabled)"
            "auxiliary:"
            "  vision:"
            "    base_url: \"${localBaseUrl}\""
            "    model: \"${localModelName}\""
            "    api_key: \"${localApiKey}\""
            "  web_extract:"
            "    base_url: \"${localBaseUrl}\""
            "    model: \"${localModelName}\""
            "    api_key: \"${localApiKey}\""
            "  compression:"
            "    timeout: 120"
            ""
          ])
          ++ optionals cfg.compression.enable [
            "# Context compression: Haiku for fast cheap summaries"
            "compression:"
            "  enabled: true"
            "  threshold: ${cfg.compression.threshold}"
            "  target_ratio: 0.25"
            "  protect_last_n: ${toString cfg.compression.protectLastN}"
            "  summary_model: \"${cfg.compression.summaryModel}\""
            "  summary_provider: \"${cfg.delegation.provider}\""
            "  summary_base_url: \"${vertexProxyBaseUrl}\""
            ""
          ]
          ++ optionals cfg.voice.enable [
            "# Voice mode: microphone input + TTS output"
            "voice:"
            "  record_key: \"${cfg.voice.recordKey}\""
            "  auto_tts: ${if cfg.voice.autoTts then "true" else "false"}"
            "  silence_threshold: ${toString cfg.voice.silenceThreshold}"
            "  silence_duration: ${toString cfg.voice.silenceDuration}"
            ""
            "stt:"
            "  provider: \"${cfg.voice.sttProvider}\""
            "  local:"
            "    model: \"${cfg.voice.sttModel}\""
            ""
            "tts:"
            "  provider: \"${cfg.voice.ttsProvider}\""
            "  edge:"
            "    voice: \"${cfg.voice.ttsVoice}\""
            ""
          ]
          ++ [
            "agent:"
            "  tool_use_enforcement: \"auto\""
            "  max_turns: ${toString cfg.agent.maxTurns}"
            "  gateway_timeout: ${toString cfg.agent.gatewayTimeout}"
          ]
          ++ optionals (cfg.agent.reasoningEffort != "") [
            "  reasoning_effort: \"${cfg.agent.reasoningEffort}\""
          ]
          ++ [
            ""
            "terminal:"
            "  backend: local"
            "  persistent_shell: true"
            "  timeout: 180"
            ""
            "memory:"
            "  provider: \"holographic\""
            "  memory_enabled: true"
            "  user_profile_enabled: true"
            "  memory_char_limit: ${toString cfg.memoryCharLimit}"
            "  user_char_limit: ${toString cfg.userCharLimit}"
            "  nudge_interval: 10"
            "  flush_min_turns: 6"
            ""
            "# Holographic memory plugin: HRR-backed compositional recall over a"
            "# local SQLite store. auto_extract pulls facts from the conversation"
            "# without requiring explicit `memory.record` calls."
            "plugins:"
            "  hermes-memory-store:"
            "    db_path: \"/Users/${user.name}/.hermes/memory_store.db\""
            "    auto_extract: true"
            ""
            "skills:"
            "  creation_nudge_interval: 15"
            ""
            "checkpoints:"
            "  enabled: true"
            "  max_snapshots: 50"
            ""
            "approvals:"
            "  mode: \"${cfg.approvals.mode}\""
            ""
            "display:"
            "  streaming: ${if cfg.display.streaming then "true" else "false"}"
            "  show_cost: ${if cfg.display.showCost then "true" else "false"}"
            "  bell_on_complete: ${if cfg.display.bellOnComplete then "true" else "false"}"
            "  show_reasoning: ${if cfg.display.showReasoning then "true" else "false"}"
            "  tool_progress: \"${cfg.display.toolProgress}\""
            "  inline_diffs: true"
          ]
          ++ optionals (cfg.skin != null) [
            "  skin: \"${cfg.skin}\""
          ]
          ++ [
            ""
            "security:"
            "  redact_secrets: true"
            "  tirith_enabled: false"
            ""
            "file_read_max_chars: ${toString cfg.fileReadMaxChars}"
          ]
        );
      };

      programs.zsh.shellInit = mkAfter (''
        # faster-whisper model is already cached locally; suppress the
        # huggingface_hub unauthenticated-request warning at transcription time.
        export HF_HUB_OFFLINE=1
        # Export the LiteLLM virtual key for ad-hoc shell use (curl,
        # debugging). The hermes config.yaml itself gets the key
        # baked in at activation time — see `home.activation
        # .hermesConfigInjectKey` below — so the daemon doesn't
        # depend on this env var being set.
        if [ -r "${toString cfg.litellm.virtualKeyFile}" ]; then
          export LITELLM_HERMES_API_KEY="$(cut -d= -f2- < "${toString cfg.litellm.virtualKeyFile}")"
        fi
      '');
    }

    # SOUL.md: global agent identity (only written when soulMd option is set)
    (mkIf (cfg.soulMd != "") {
      home-manager.users.${user.name}.home.file.".hermes/SOUL.md".text = cfg.soulMd;
    })

    # Custom display skins: ~/.hermes/skins/<name>.yaml
    (mkIf (cfg.skin != null) {
      home-manager.users.${user.name}.home.file.".hermes/skins/${cfg.skin}.yaml".text =
        builtins.readFile (
          pkgs.writeText "${cfg.skin}-skin.yaml" ''
            name: ${cfg.skin}
            description: Schrodinger Inc. — physics-based molecular discovery & drug design theme
            colors:
              banner_border: "#1032CF"
              banner_title: "#FFFFFF"
              banner_accent: "#A6DDF5"
              banner_dim: "#534698"
              banner_text: "#E8EDF5"
              ui_accent: "#2A4EEF"
              ui_label: "#1032CF"
              ui_ok: "#4CAF50"
              ui_error: "#EF5350"
              ui_warn: "#F37C28"
              prompt: "#E8EDF5"
              input_rule: "#1032CF"
              response_border: "#2A4EEF"
              status_bar_bg: "#12122D"
              status_bar_text: "#E8EDF5"
              status_bar_strong: "#A6DDF5"
              status_bar_dim: "#534698"
              status_bar_good: "#4CAF50"
              status_bar_warn: "#F37C28"
              status_bar_bad: "#2A4EEF"
              status_bar_critical: "#EF5350"
              voice_status_bg: "#12122D"
              completion_menu_bg: "#0D0D22"
              completion_menu_current_bg: "#1A1A45"
              completion_menu_meta_bg: "#12122D"
              completion_menu_meta_current_bg: "#1E1E50"
              session_label: "#2A4EEF"
              session_border: "#534698"
            spinner:
              waiting_faces:
                - "(⚛)"
                - "(◈)"
                - "(◎)"
                - "(⊕)"
                - "(⬡)"
              thinking_faces:
                - "(⚛)"
                - "(◈)"
                - "(◎)"
                - "(⌁)"
                - "(⊕)"
              thinking_verbs:
                - "simulating conformation"
                - "computing binding affinity"
                - "running FEP+ calculation"
                - "optimizing scaffold"
                - "mapping electron density"
                - "sampling molecular dynamics"
                - "equilibrating system"
                - "minimizing energy"
              wings:
                - ["⟪⚛", "⚛⟫"]
                - ["⟪◈", "◈⟫"]
                - ["⟪⊕", "⊕⟫"]
                - ["⟪⬡", "⬡⟫"]
            branding:
              agent_name: "Schrodinger Agent"
              welcome: "Welcome to Schrödinger. Physics-based AI for molecular discovery. Type your message or /help for commands."
              goodbye: "Until next simulation. ⚛"
              response_label: " ⚛ Schrodinger "
              prompt_symbol: "⚛ ❯ "
              help_header: "(⚛) Available Commands"
            tool_prefix: "│"
            tool_emojis:
              terminal: "⚙"
              web_search: "◎"
              read_file: "◇"
              write_file: "◆"
              search_files: "⊕"
              execute_code: "⌁"
              browser_navigate: "◈"
              delegate_task: "▣"
              mixture_of_agents: "⚛"
              memory: "◐"
              clarify: "?"
              cronjob: "↻"
              process: "⚙"
              todo: "☐"
            banner_logo: |
              [#2A4EEF]  ⚛[/]  [bold #E8EDF5] S C H R Ö D I N G E R [/]
            banner_hero: |
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠞⠛⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢷⣄⠀⠀⠀⠀⠀⠀⠀[/]
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⢦⡀⠀⠀⠀⠀[/]
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣤⣤⣤⣤⣤⣤⣤⣤⣄⠀⠀⠀⠀⠀⠈⢻⡆⠀⠀[/]
              [#1032CF]⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠀⠀⢀⡴⠟⠁⠀⠀⠀⠀⠈⠙⠻⢷⣤⣤⣤⡿⠟⠁⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀[/]
              [#2A4EEF]⠀⠀⢀⡴⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⢠⠟⠁⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠞⠁⠀⠀⠀⠀[/]
              [bold #2A4EEF]⢠⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠀⠀⢀⡴⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀⠞⠁⠀⠀⠀⠀⠀⠀[/]
              [bold #1032CF]⠈⠙⢷⣤⣀⣀⣀⡴⠋⠀⠀⠈⠙⢦⣄⣀⡴⠟⠁⠀⠀⠀⠀⢀⡴⠋⠀⠀⢀⡴⠋⠀⠀⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [bold #A6DDF5]⠀⠀⠀⠈⠙⠻⢦⣤⣀⣀⣀⡴⠋⠀⠀⠈⠙⠻⢷⣤⣀⣀⣀⡴⠋⠀⠀⢀⡴⠋⠀⠀⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [bold #A6DDF5]⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢦⣤⣀⣀⣀⡴⠋⠀⠀⠈⠙⠻⢦⣤⣀⣀⣀⡴⠋⠀⠀⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [#2A4EEF]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢦⣤⣀⣀⣀⡴⠋⠀⠀⠈⠙⠻⢷⣤⣀⣀⣀⡴⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢦⣤⣀⣀⣀⡴⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [dim #534698]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢦⣤⣤⣤⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀[/]
              [bold #2A4EEF]⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀ ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀ [/]
          ''
        );
    })

    # NixOS (Linux): Ollama as a systemd service
    (optionalAttrs isLinux {
      services.ollama = {
        enable = true;
        port = cfg.ollamaPort;
        loadModels = [ cfg.localModel ] ++ cfg.extraOllamaModels;
      };
    })

    # NixOS (Linux): portaudio for CLI voice mode microphone input
    (optionalAttrs isLinux (
      mkIf cfg.voice.enable {
        environment.systemPackages = [ pkgs.portaudio ];
      }
    ))

    # Darwin (macOS): Ollama via Homebrew cask (launchd-managed)
    (mkIf (isDarwin && !cfg.exo.enable) {
      homebrew.casks = [ "ollama" ];
    })

    # Darwin (macOS): portaudio for CLI voice mode microphone input
    (optionalAttrs isDarwin (
      mkIf cfg.voice.enable {
        homebrew.brews = [ "portaudio" ];
      }
    ))
  ]);
}
