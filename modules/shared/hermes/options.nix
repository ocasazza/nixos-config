{ lib, defaultPackage }:

with lib;

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

    # ── Main model configuration ──────────────────────────────────────
    # Controls the default model and provider for Hermes. This overrides
    # the litellm/vertexProxy automatic selection when set.
    mainModel = {
      provider = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Provider for the main model. Options: "gemini" (OAuth), "anthropic"
          (Vertex proxy), "litellm" (LiteLLM router). When null, defaults to
          "litellm" if litellm.enable=true, otherwise "anthropic".
        '';
      };

      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Model name for the main provider. Required when mainModel.provider
          is set. Examples: "gemini-3-pro", "claude-sonnet-4-7",
          "pdx-nxst-003-qwen3.6-35b-a3b".
        '';
      };

      baseURL = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Base URL for the main provider. Optional - most providers use
          auto-resolution. Set this for custom endpoints.
        '';
      };

      apiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          API key for the main provider. Optional - OAuth providers (gemini)
          don't need this. Use environment variable references like
          "$LITELLM_HERMES_API_KEY".
        '';
      };
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
    # Route all hermes calls through the LiteLLM proxy on pdx-nxst-003:
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
          (`http://pdx-nxst-001.schrodinger.com:8080/litellm`) so every
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

          On pdx-nxst-003 this is
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
          in non-vertex mode). Defaults to pdx-nxst-003-qwen3.6-35b-a3b.
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
        default = "0.10";
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
        default = "litellm/gfr-osx26-02-gpt-oss-120b";
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
}
