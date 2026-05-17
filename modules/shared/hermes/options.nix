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
    # Direct configuration: set provider + model, optionally override
    # base_url and api_key. Built-in providers: gemini, anthropic,
    # openai-codex, copilot, zai, kimi-coding, minimax, deepseek,
    # alibaba, ai-gateway, opencode-zen, opencode-go, hf, nous.
    # For providers not in the built-in registry, use base_url + api_key
    # (OpenAI-compatible custom endpoint) or add a custom_providers entry.
    mainModel = {
      provider = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Built-in provider name for the main model. Examples: "gemini"
          (uses gcloud ADC OAuth), "anthropic" (uses ANTHROPIC_TOKEN),
          "openai-codex" (ChatGPT OAuth). When null and baseURL is set,
          hermes treats it as a custom OpenAI-compatible endpoint.
        '';
      };

      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Model name / slug. Examples: "gemini-2.5-pro",
          "claude-sonnet-4-7", "gpt-5.3-codex".
        '';
      };

      baseURL = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Direct OpenAI-compatible endpoint URL. Overrides the provider's
          default base URL. Use this for Azure OpenAI, Vertex proxy, or
          any custom endpoint. Example:
          "https://schrodinger-code.openai.azure.com/openai/deployments/Kimi-K2.6".
        '';
      };

      apiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          API key for the direct endpoint. For built-in providers this is
          usually unnecessary (OAuth / env-var resolution handles auth).
          For custom endpoints (Azure, Vertex proxy) set this to a
          placeholder like "$AZURE_API_KEY" or "$VERTEX_PROXY_ID_TOKEN"
          and wire the corresponding sops secret + activation script.
        '';
      };

      geminiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a sops-decrypted file containing the Gemini API key
          (single `GEMINI_API_KEY=...` line). When set, the activation
          script replaces `$GEMINI_API_KEY` in the generated config with
          the real key. Used when mainModel.provider = "gemini" and you
          prefer API-key auth over gcloud ADC OAuth.
        '';
      };

      vertexProxyIdToken = mkOption {
        type = types.bool;
        default = false;
        description = ''
          When true, the activation script reads the current gcloud
          id-token and replaces `$VERTEX_PROXY_ID_TOKEN` in the generated
          config. Use this when mainModel.baseURL points at the
          Schrodinger vertex proxy.
        '';
      };

      models = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              contextLength = mkOption {
                type = types.int;
                default = 128000;
                description = "Context window length for this model";
              };
            };
          }
        );
        default = { };
        description = ''
          Models available via the main model custom provider. When
          non-empty, these populate the /model picker for the custom-main
          provider entry. Keys are model IDs, values are per-model config.
        '';
      };
    };

    # ── Vertex AI Claude via LiteLLM passthrough ──────────────────────
    # Adds a `vertex-proxy` providers entry so Hermes can reach Claude
    # models on Vertex AI through the LiteLLM /vertex passthrough.
    # Auth uses gcloud identity tokens (replaced at activation time).
    # Switch at runtime with: /model vertex-proxy:claude-opus-4-7
    vertexProxy = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Add a vertex-proxy providers entry pointing at the LiteLLM
          /vertex passthrough. When enabled, Hermes can reach Claude
          models on Vertex AI via /model vertex-proxy:<model>.
          The gcloud identity token is injected at activation time.
        '';
      };

      endpoint = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.vertexPassthroughEndpoint;
        description = ''
          LiteLLM vertex passthrough URL. Defaults to the Caddy-fronted
          FQDN (http://litellm.pdx-nxst-001.schrodinger.com:8080/vertex/v1).
          The /v1 suffix is automatically stripped for anthropic_messages mode.
        '';
      };

      models = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              contextLength = mkOption {
                type = types.int;
                default = 200000;
                description = "Context window length for this model";
              };
            };
          }
        );
        default = {
          "claude-sonnet-4-6" = {
            contextLength = 200000;
          };
          "claude-opus-4-7" = {
            contextLength = 200000;
          };
        };
        description = ''
          Models available via vertex-proxy. Keys are model IDs shown
          in the /model picker. Defaults to Claude Sonnet 4 + Opus 4.7.
        '';
      };
    };

    # ── LiteLLM-routed path ───────────────────────────────────────────
    # Route local model calls through the LiteLLM proxy on pdx-nxst-001.
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

          On darwin hosts this is
          `config.sops.secrets.litellm-key-local-svc-hermes.path`
          (local-compute service account key minted on pdx-nxst-001).
        '';
      };

      defaultLocalGroup = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.defaultLocalGroup;
        description = ''
          LiteLLM model alias hermes refers to when picking a
          "local" model (delegation in non-vertex mode, auxiliary
          in non-vertex mode). Defaults to qwen3.6-35b-a3b.
        '';
      };

      models = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              contextLength = mkOption {
                type = types.int;
                default = 131072;
                description = "Context window length for this model";
              };
            };
          }
        );
        default = { };
        description = ''
          Models exposed in the /model picker under the litellm provider.
          When non-empty, a 'litellm' providers entry is generated pointing
          at litellm.endpoint/v1. Keys must be valid LiteLLM model aliases.
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
        default = "Kimi-K2.6";
        description = "Model to use for subagent delegation";
      };

      provider = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Built-in provider for subagent delegation. When null and
          baseURL is set, hermes uses the direct endpoint. Examples:
          "gemini", "anthropic", "openrouter", "zai".
        '';
      };

      baseURL = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Direct OpenAI-compatible endpoint for subagents. Overrides
          provider resolution. Use this for Azure OpenAI, local vLLM,
          or any custom endpoint. Falls back to OPENAI_API_KEY env var
          when apiKey is not set.
        '';
      };

      apiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          API key for the delegation endpoint. Set to a placeholder like
          "$AZURE_API_KEY" and wire the sops secret + activation script.
          When null and baseURL is set, hermes falls back to OPENAI_API_KEY.
        '';
      };

      azureKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a sops-decrypted file containing the Azure OpenAI API
          key (single `AZURE_API_KEY=...` line). When set, the activation
          script replaces `$AZURE_API_KEY` in the generated config. Use
          this when delegation.baseURL points at an Azure OpenAI endpoint.
        '';
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

      models = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              contextLength = mkOption {
                type = types.int;
                default = 128000;
                description = "Context window length for this model";
              };
            };
          }
        );
        default = { };
        description = ''
          Models available via the delegation provider. When non-empty,
          these populate the /model picker for the delegation custom provider.
          Keys are model IDs, values are per-model config.
        '';
      };
    };

    auxiliary = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auxiliary model configuration for side tasks";
      };

      provider = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Built-in provider for auxiliary tasks (vision, web_extract).
          When null and baseURL is set, hermes uses the direct endpoint.
          "gemini" is recommended for vision (multimodal).
        '';
      };

      model = mkOption {
        type = types.str;
        default = "gemini-2.5-pro";
        description = "Model for auxiliary tasks (vision, web_extract)";
      };

      baseURL = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Direct OpenAI-compatible endpoint for auxiliary tasks. Overrides
          provider resolution. Use this for Gemini API, local vision models,
          or any custom endpoint.
        '';
      };

      apiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          API key for the auxiliary endpoint. Set to a placeholder like
          "$GEMINI_API_KEY" and wire the sops secret + activation script.
        '';
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
