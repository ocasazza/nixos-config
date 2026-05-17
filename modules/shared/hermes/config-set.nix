{
  lib,
  cfg,
  user,
  config ? null,
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

  # Helper to handle SOPS placeholders if config is provided
  placeholder = name: if config != null then config.sops.placeholder."${name}" else "$${${name}}";

  # Resolve API keys: use SOPS placeholder if a keyFile is provided, otherwise use the literal apiKey
  mainModelApiKey =
    if cfg.mainModel.geminiKeyFile != null then
      placeholder "gemini-api-key"
    else if cfg.mainModel.vertexProxyIdToken then
      "$VERTEX_PROXY_ID_TOKEN"
    else
      cfg.mainModel.apiKey;

  delegationApiKey =
    if cfg.delegation.azureKeyFile != null then
      placeholder "atlassian-api-token" # Example: mapping to known secret
    else
      cfg.delegation.apiKey;

in
{
  model = mkMerge [
    (optionalAttrs (cfg.mainModel.name != null) { default = cfg.mainModel.name; })
    (optionalAttrs (mainModelProvider != null) { provider = mainModelProvider; })
    (optionalAttrs (cfg.mainModel.baseURL != null) { base_url = cfg.mainModel.baseURL; })
    (optionalAttrs (mainModelApiKey != null) { api_key = mainModelApiKey; })
  ];

  delegation = mkIf cfg.delegation.enable (mkMerge [
    (optionalAttrs (cfg.delegation.model != null) { model = cfg.delegation.model; })
    (optionalAttrs (delegationProvider != null) { provider = delegationProvider; })
    (optionalAttrs (cfg.delegation.baseURL != null) { base_url = cfg.delegation.baseURL; })
    (optionalAttrs (delegationApiKey != null) { api_key = delegationApiKey; })
    {
      max_iterations = cfg.delegation.maxIterations;
      default_toolsets = cfg.delegation.defaultToolsets;
    }
  ]);

  auxiliary = mkIf cfg.auxiliary.enable {
    vision = mkMerge [
      (optionalAttrs (cfg.auxiliary.model != null) { model = cfg.auxiliary.model; })
      (optionalAttrs (cfg.auxiliary.provider != null) { provider = cfg.auxiliary.provider; })
      (optionalAttrs (cfg.auxiliary.baseURL != null) { base_url = cfg.auxiliary.baseURL; })
      (optionalAttrs (cfg.auxiliary.apiKey != null) { api_key = cfg.auxiliary.apiKey; })
    ];
    web_extract = mkMerge [
      (optionalAttrs (cfg.auxiliary.model != null) { model = cfg.auxiliary.model; })
      (optionalAttrs (cfg.auxiliary.provider != null) { provider = cfg.auxiliary.provider; })
      (optionalAttrs (cfg.auxiliary.baseURL != null) { base_url = cfg.auxiliary.baseURL; })
      (optionalAttrs (cfg.auxiliary.apiKey != null) { api_key = cfg.auxiliary.apiKey; })
    ];
    compression.timeout = 120;
  };

  compression = mkIf cfg.compression.enable {
    enabled = true;
    threshold = cfg.compression.threshold;
    target_ratio = 0.25;
    protect_last_n = cfg.compression.protectLastN;
    summary_model = cfg.compression.summaryModel;
    summary_provider = "litellm";
    summary_base_url = "${litellmEndpoint}/v1";
  };

  voice = mkIf cfg.voice.enable {
    record_key = cfg.voice.recordKey;
    auto_tts = cfg.voice.autoTts;
    silence_threshold = cfg.voice.silenceThreshold;
    silence_duration = cfg.voice.silenceDuration;
  };

  stt = mkIf cfg.voice.enable {
    provider = cfg.voice.sttProvider;
    local.model = cfg.voice.sttModel;
  };

  tts = mkIf cfg.voice.enable {
    provider = cfg.voice.ttsProvider;
    edge.voice = cfg.voice.ttsVoice;
  };

  providers =
    mkIf
      (
        mainModelIsCustom
        || delegationIsCustom
        || cfg.vertexProxy.enable
        || (cfg.litellm.enable && cfg.litellm.models != { })
      )
      (mkMerge [
        (optionalAttrs mainModelIsCustom {
          custom-main = {
            name = "Custom Main";
            base_url = cfg.mainModel.baseURL;
            api_key = if cfg.mainModel.apiKey != null then cfg.mainModel.apiKey else "";
            api_mode = "chat_completions";
            models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.mainModel.models;
          };
        })
        (optionalAttrs delegationIsCustom {
          custom-delegation = {
            name = "Custom Delegation";
            base_url = cfg.delegation.baseURL;
            api_key = if cfg.delegation.apiKey != null then cfg.delegation.apiKey else "";
            api_mode = "chat_completions";
            models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.delegation.models;
          };
        })
        (optionalAttrs cfg.vertexProxy.enable {
          vertex-proxy = {
            name = "Vertex Proxy (Claude via LiteLLM)";
            base_url = lib.removeSuffix "/v1" cfg.vertexProxy.endpoint;
            api_key = "$VERTEX_PROXY_ID_TOKEN";
            api_mode = "anthropic_messages";
            models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.vertexProxy.models;
          };
        })
        (optionalAttrs (cfg.litellm.enable && cfg.litellm.models != { }) {
          litellm = {
            name = "Schrodinger LiteLLM";
            base_url = "${litellmEndpoint}/v1";
            api_key = "env:LITELLM_HERMES_API_KEY";
            api_mode = "chat_completions";
            models = mapAttrs (_: m: { context_length = m.contextLength; }) cfg.litellm.models;
          };
        })
      ]);

  agent = {
    tool_use_enforcement = "auto";
    max_turns = cfg.agent.maxTurns;
    gateway_timeout = cfg.agent.gatewayTimeout;
    reasoning_effort = mkIf (cfg.agent.reasoningEffort != "") cfg.agent.reasoningEffort;
  };

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
      db_path = "/Users/${user.name}/.hermes/memory_store.db";
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
