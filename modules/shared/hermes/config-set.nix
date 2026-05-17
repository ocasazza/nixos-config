{
  lib,
  cfg,
  config,
}:

with lib;

let
  litellmEndpoint = cfg.litellm.endpoint;

  # When baseURL is set but provider is null, hermes needs an explicit
  # provider name pointing at a custom_providers entry.
  mainModelIsCustom = cfg.mainModel.provider == null && cfg.mainModel.baseURL != null;
  mainModelProvider = if mainModelIsCustom then "custom-main" else cfg.mainModel.provider;

  delegationIsCustom =
    cfg.delegation.enable && cfg.delegation.provider == null && cfg.delegation.baseURL != null;
  delegationProvider = if delegationIsCustom then "custom-delegation" else cfg.delegation.provider;

  # Resolve API keys: use SOPS placeholder if a keyFile is provided, otherwise use the literal apiKey
  mainModelApiKey =
    if cfg.mainModel.geminiKeyFile != null then
      config.sops.placeholder."gemini-enterprise-api-key"
    else if cfg.mainModel.vertexProxyIdToken then
      "$VERTEX_PROXY_ID_TOKEN"
    else
      cfg.mainModel.apiKey;

  delegationApiKey =
    if cfg.delegation.azureKeyFile != null then
      config.sops.placeholder."azure-api-key-opencode-darwin"
    else
      cfg.delegation.apiKey;

  hasProviders =
    mainModelIsCustom
    || delegationIsCustom
    || cfg.vertexProxy.enable
    || (cfg.litellm.enable && cfg.litellm.models != { });

in
# Use // and optionalAttrs (plain Nix) rather than mkMerge/mkIf so that
# builtins.toJSON produces a flat object hermes can parse. mkMerge/mkIf
# produce _type:"merge"/_type:"if" objects outside the NixOS module
# evaluator, which break hermes's provider lookup in headless mode.
{
  model =
    (optionalAttrs (cfg.mainModel.name != null) { default = cfg.mainModel.name; })
    // (optionalAttrs (mainModelProvider != null) { provider = mainModelProvider; })
    // (optionalAttrs (cfg.mainModel.baseURL != null) { base_url = cfg.mainModel.baseURL; })
    // (optionalAttrs (mainModelApiKey != null) { api_key = mainModelApiKey; });

  agent = {
    tool_use_enforcement = "auto";
    max_turns = cfg.agent.maxTurns;
    gateway_timeout = cfg.agent.gatewayTimeout;
  }
  // (optionalAttrs (cfg.agent.reasoningEffort != "") {
    reasoning_effort = cfg.agent.reasoningEffort;
  });

  terminal = {
    backend = "local";
    persistent_shell = true;
    timeout = 180;
  };

  memory = {
    provider = "holographic";
    memory_enabled = true;
    user_profile_enabled = true;
    memory_char_limit = cfg.memoryCharLimit;
    user_char_limit = cfg.userCharLimit;
    nudge_interval = 10;
    flush_min_turns = 6;
  };

  plugins = {
    hermes-memory-store = {
      db_path = "${config.home.homeDirectory}/.hermes/memory_store.db";
      auto_extract = true;
    };
  };

  skills = {
    creation_nudge_interval = 15;
  };

  checkpoints = {
    enabled = true;
    max_snapshots = 50;
  };

  approvals = {
    mode = cfg.approvals.mode;
  };

  display = {
    streaming = cfg.display.streaming;
    show_cost = cfg.display.showCost;
    bell_on_complete = cfg.display.bellOnComplete;
    show_reasoning = cfg.display.showReasoning;
    tool_progress = cfg.display.toolProgress;
    inline_diffs = true;
    skin = cfg.skin;
  };

  security = {
    redact_secrets = true;
    tirith_enabled = false;
  };

  file_read_max_chars = cfg.fileReadMaxChars;
}
// (optionalAttrs cfg.delegation.enable {
  delegation =
    (optionalAttrs (cfg.delegation.model != null) { model = cfg.delegation.model; })
    // (optionalAttrs (delegationProvider != null) { provider = delegationProvider; })
    // (optionalAttrs (cfg.delegation.baseURL != null) { base_url = cfg.delegation.baseURL; })
    // (optionalAttrs (delegationApiKey != null) { api_key = delegationApiKey; })
    // {
      max_iterations = cfg.delegation.maxIterations;
      default_toolsets = cfg.delegation.defaultToolsets;
    };
})
// (optionalAttrs cfg.auxiliary.enable {
  auxiliary = {
    vision =
      (optionalAttrs (cfg.auxiliary.model != null) { model = cfg.auxiliary.model; })
      // (optionalAttrs (cfg.auxiliary.provider != null) { provider = cfg.auxiliary.provider; })
      // (optionalAttrs (cfg.auxiliary.baseURL != null) { base_url = cfg.auxiliary.baseURL; })
      // (optionalAttrs (cfg.auxiliary.apiKey != null) { api_key = cfg.auxiliary.apiKey; });
    web_extract =
      (optionalAttrs (cfg.auxiliary.model != null) { model = cfg.auxiliary.model; })
      // (optionalAttrs (cfg.auxiliary.provider != null) { provider = cfg.auxiliary.provider; })
      // (optionalAttrs (cfg.auxiliary.baseURL != null) { base_url = cfg.auxiliary.baseURL; })
      // (optionalAttrs (cfg.auxiliary.apiKey != null) { api_key = cfg.auxiliary.apiKey; });
    compression.timeout = 120;
  };
})
// (optionalAttrs cfg.compression.enable {
  compression = {
    enabled = true;
    threshold = cfg.compression.threshold;
    target_ratio = 0.25;
    protect_last_n = cfg.compression.protectLastN;
    summary_model = cfg.compression.summaryModel;
    summary_provider = "litellm";
    summary_base_url = "${litellmEndpoint}/v1";
  };
})
// (optionalAttrs cfg.voice.enable {
  voice = {
    record_key = cfg.voice.recordKey;
    auto_tts = cfg.voice.autoTts;
    silence_threshold = cfg.voice.silenceThreshold;
    silence_duration = cfg.voice.silenceDuration;
  };
  stt = {
    provider = cfg.voice.sttProvider;
    local.model = cfg.voice.sttModel;
  };
  tts = {
    provider = cfg.voice.ttsProvider;
    edge.voice = cfg.voice.ttsVoice;
  };
})
// (optionalAttrs hasProviders {
  providers =
    (optionalAttrs mainModelIsCustom {
      custom-main = {
        name = "Custom Main";
        base_url = cfg.mainModel.baseURL;
        api_key = if cfg.mainModel.apiKey != null then cfg.mainModel.apiKey else "";
        api_mode = "chat_completions";
        models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.mainModel.models;
      };
    })
    // (optionalAttrs delegationIsCustom {
      custom-delegation = {
        name = "Custom Delegation";
        base_url = cfg.delegation.baseURL;
        api_key = if cfg.delegation.apiKey != null then cfg.delegation.apiKey else "";
        api_mode = "chat_completions";
        models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.delegation.models;
      };
    })
    // (optionalAttrs cfg.vertexProxy.enable {
      vertex-proxy = {
        name = "Vertex Proxy (Claude via LiteLLM)";
        base_url = lib.removeSuffix "/v1" cfg.vertexProxy.endpoint;
        api_key = "$VERTEX_PROXY_ID_TOKEN";
        api_mode = "anthropic_messages";
        models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.vertexProxy.models;
      };
    })
    // (optionalAttrs (cfg.litellm.enable && cfg.litellm.models != { }) {
      litellm = {
        name = "Schrodinger LiteLLM";
        base_url = "${litellmEndpoint}/v1";
        api_key = config.sops.placeholder."hermes-litellm-key";
        api_mode = "chat_completions";
        models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.litellm.models;
      };
    });
})
