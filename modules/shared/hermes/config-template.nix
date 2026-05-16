{
  lib,
  cfg,
  user,
}:

with lib;

let
  litellmEndpoint = cfg.litellm.endpoint;

  # When baseURL is set but provider is null, hermes needs an explicit
  # provider name pointing at a custom_providers entry. Without it,
  # hermes auto-detects a built-in provider (e.g. google-gemini-cli)
  # and ignores the base_url entirely.
  mainModelIsCustom = cfg.mainModel.provider == null && cfg.mainModel.baseURL != null;
  mainModelProvider = if mainModelIsCustom then "custom-main" else cfg.mainModel.provider;

  delegationIsCustom =
    cfg.delegation.enable && cfg.delegation.provider == null && cfg.delegation.baseURL != null;
  delegationProvider = if delegationIsCustom then "custom-delegation" else cfg.delegation.provider;
in
concatStringsSep "\n" (
  (
    # ── Main Model Configuration ──────────────────────────────────────
    [
      "model:"
    ]
    ++ (optionals (cfg.mainModel.name != null) [
      "  default: \"${cfg.mainModel.name}\""
    ])
    ++ (optionals (mainModelProvider != null) [
      "  provider: \"${mainModelProvider}\""
    ])
    ++ (optionals (cfg.mainModel.baseURL != null) [
      "  base_url: \"${cfg.mainModel.baseURL}\""
    ])
    ++ (optionals (cfg.mainModel.apiKey != null) [
      "  api_key: \"${cfg.mainModel.apiKey}\""
    ])
    ++ [ "" ]
  )
  # ── Delegation Configuration ──────────────────────────────────────
  # Subagent provider:model pair. Use base_url + api_key for custom
  # endpoints (Azure, local vLLM) or provider for built-in registry
  # entries (gemini, anthropic, openrouter, etc.).
  ++ optionals cfg.delegation.enable (
    [
      "delegation:"
    ]
    ++ (optionals (cfg.delegation.model != null) [
      "  model: \"${cfg.delegation.model}\""
    ])
    ++ (optionals (delegationProvider != null) [
      "  provider: \"${delegationProvider}\""
    ])
    ++ (optionals (cfg.delegation.baseURL != null) [
      "  base_url: \"${cfg.delegation.baseURL}\""
    ])
    ++ (optionals (cfg.delegation.apiKey != null) [
      "  api_key: \"${cfg.delegation.apiKey}\""
    ])
    ++ [
      "  max_iterations: ${toString cfg.delegation.maxIterations}"
      "  default_toolsets: [${
          concatStringsSep ", " (map (t: "\"${t}\"") cfg.delegation.defaultToolsets)
        }]"
      ""
    ]
  )
  # ── Auxiliary Configuration ───────────────────────────────────────
  # Side-task models (vision, web_extract). Same resolution rules as
  # delegation: provider for built-in, base_url+api_key for custom.
  ++ optionals cfg.auxiliary.enable (
    [
      "auxiliary:"
      "  vision:"
    ]
    ++ (optionals (cfg.auxiliary.model != null) [
      "    model: \"${cfg.auxiliary.model}\""
    ])
    ++ (optionals (cfg.auxiliary.provider != null) [
      "    provider: \"${cfg.auxiliary.provider}\""
    ])
    ++ (optionals (cfg.auxiliary.baseURL != null) [
      "    base_url: \"${cfg.auxiliary.baseURL}\""
    ])
    ++ (optionals (cfg.auxiliary.apiKey != null) [
      "    api_key: \"${cfg.auxiliary.apiKey}\""
    ])
    ++ [
      "  web_extract:"
    ]
    ++ (optionals (cfg.auxiliary.model != null) [
      "    model: \"${cfg.auxiliary.model}\""
    ])
    ++ (optionals (cfg.auxiliary.provider != null) [
      "    provider: \"${cfg.auxiliary.provider}\""
    ])
    ++ (optionals (cfg.auxiliary.baseURL != null) [
      "    base_url: \"${cfg.auxiliary.baseURL}\""
    ])
    ++ (optionals (cfg.auxiliary.apiKey != null) [
      "    api_key: \"${cfg.auxiliary.apiKey}\""
    ])
    ++ [
      "  compression:"
      "    timeout: 120"
      ""
    ]
  )
  ++ optionals cfg.compression.enable [
    "compression:"
    "  enabled: true"
    "  threshold: ${cfg.compression.threshold}"
    "  target_ratio: 0.25"
    "  protect_last_n: ${toString cfg.compression.protectLastN}"
    "  summary_model: \"${cfg.compression.summaryModel}\""
    "  summary_provider: \"litellm\""
    "  summary_base_url: \"${litellmEndpoint}/v1\""
    ""
  ]
  ++ optionals cfg.voice.enable [
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
  # ── Custom Providers ──────────────────────────────────────────────
  # Register custom OpenAI-compatible endpoints so hermes can resolve
  # them by name instead of falling back to auto-detection.
  # Uses the `providers:` dict format (new-style) with `models:` sub-dicts
  # so the /model picker shows available models per provider.
  ++ optionals (mainModelIsCustom || delegationIsCustom || cfg.vertexProxy.enable) [
    "providers:"
  ]
  ++ optionals mainModelIsCustom (
    [ "  custom-main:" ]
    ++ [ "    name: \"Custom Main\"" ]
    ++ [ "    base_url: \"${cfg.mainModel.baseURL}\"" ]
    ++ [ "    api_key: \"${if cfg.mainModel.apiKey != null then cfg.mainModel.apiKey else ""}\"" ]
    ++ [ "    api_mode: \"chat_completions\"" ]
    ++ (optionals (cfg.mainModel.models != { }) (
      [ "    models:" ]
      ++ (mapAttrsToList (
        name: m: "      ${name}:\n        context_length: ${toString m.contextLength}"
      ) cfg.mainModel.models)
    ))
  )
  ++ optionals delegationIsCustom (
    [ "  custom-delegation:" ]
    ++ [ "    name: \"Custom Delegation\"" ]
    ++ [ "    base_url: \"${cfg.delegation.baseURL}\"" ]
    ++ [ "    api_key: \"${if cfg.delegation.apiKey != null then cfg.delegation.apiKey else ""}\"" ]
    ++ [ "    api_mode: \"chat_completions\"" ]
    ++ (optionals (cfg.delegation.models != { }) (
      [ "    models:" ]
      ++ (mapAttrsToList (
        name: m: "      ${name}:\n        context_length: ${toString m.contextLength}"
      ) cfg.delegation.models)
    ))
  )
  ++ optionals cfg.vertexProxy.enable (
    let
      # Strip trailing /v1 for anthropic_messages mode — the SDK appends
      # /v1/messages automatically. A double /v1/v1/messages results in 404.
      vertexBase = lib.removeSuffix "/v1" cfg.vertexProxy.endpoint;
    in
    [ "  vertex-proxy:" ]
    ++ [ "    name: \"Vertex Proxy (Claude via LiteLLM)\"" ]
    ++ [ "    base_url: \"${vertexBase}\"" ]
    ++ [ "    api_key: \"$VERTEX_PROXY_ID_TOKEN\"" ]
    ++ [ "    api_mode: \"anthropic_messages\"" ]
    ++ (optionals (cfg.vertexProxy.models != { }) (
      [ "    models:" ]
      ++ (mapAttrsToList (
        name: m: "      ${name}:\n        context_length: ${toString m.contextLength}"
      ) cfg.vertexProxy.models)
    ))
  )
  ++ optionals (mainModelIsCustom || delegationIsCustom || cfg.vertexProxy.enable) [
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
    "  skin: \"${cfg.skin}\""
    ""
    "security:"
    "  redact_secrets: true"
    "  tirith_enabled: false"
    ""
    "file_read_max_chars: ${toString cfg.fileReadMaxChars}"
  ]
)
