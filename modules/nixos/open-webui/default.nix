# Open WebUI as a chat frontend for the local vLLM endpoint(s).
#
# Open WebUI talks to any OpenAI-compatible backend via OPENAI_API_BASE_URLS,
# so we just hand it the URLs from `local.vllm.services` and the model
# selector in the UI populates from `/v1/models` automatically. Adding a
# new vllm service (e.g. an embedding endpoint) wires it into the chat UI
# on the next switch — no extra config needed here.
#
# What this module owns:
#   * `services.open-webui` enable + port + state dir
#   * Auto-wiring of `OPENAI_API_BASE_URLS` from local.vllm.services
#   * A sensible default env block (telemetry off, signup gated) that can
#     be overridden via `extraEnvironment`
#
# What it does NOT own (yet):
#   * TLS / reverse proxy — fine on a LAN-only box, add caddy/nginx later
#   * Embedding model wiring — once luna serves an embedding endpoint,
#     either set `embeddingEndpoint` here or let users pick it via the UI
#   * RAG document store — Open WebUI's built-in vector DB is enough for
#     ad-hoc uploads; the Obsidian vault is queried by LocalGPT, not here
#
# Usage:
#   local.openWebUI = {
#     enable = true;
#     openFirewall = true;
#   };
#
# Verify (after `nixos-rebuild switch`):
#   curl -sS http://luna.local:8080/health
#   open http://luna.local:8080      # first-user signup → becomes admin
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.openWebUI;
  vllmCfg =
    config.local.vllm or {
      enable = false;
      services = { };
    };

  # Auto-derive backend URLs from every enabled vLLM service. Open WebUI
  # accepts a `;`-separated list in OPENAI_API_BASE_URLS and probes each
  # one's `/models` endpoint to populate the model picker.
  derivedEndpoints = mapAttrsToList (_: svc: "http://127.0.0.1:${toString svc.port}/v1") (
    if vllmCfg.enable then vllmCfg.services else { }
  );

  endpoints = if cfg.openaiBaseURLs != null then cfg.openaiBaseURLs else derivedEndpoints;

  # vLLM ignores Authorization but Open WebUI sends one regardless and
  # bails if OPENAI_API_KEYS is empty. The literal "none" matches what
  # the Open WebUI docs recommend for upstreams without auth.
  apiKeys = map (_: cfg.apiKey) endpoints;

  baseEnvironment = {
    # Bind explicitly; the upstream module's `host` option also passes
    # this but we set it for any sub-process / health probe that reads
    # the env directly.
    HOST = cfg.host;
    PORT = toString cfg.port;

    # Backend wiring. `;` separator is Open WebUI's convention.
    OPENAI_API_BASE_URLS = concatStringsSep ";" endpoints;
    OPENAI_API_KEYS = concatStringsSep ";" apiKeys;

    # No Ollama — we serve through vllm only. Disabling the probe avoids
    # a noisy startup log line every restart.
    ENABLE_OLLAMA_API = "false";

    # Auth posture: signup on by default so the first browser hit creates
    # the admin user. Flip `signupEnabled = false` after that to lock the
    # instance down.
    ENABLE_SIGNUP = boolToString cfg.signupEnabled;
    DEFAULT_USER_ROLE = cfg.defaultUserRole;
    WEBUI_AUTH = boolToString cfg.requireAuth;

    # Don't phone home. The dataset Open WebUI sends to its analytics
    # endpoint includes model names and prompt lengths.
    ANONYMIZED_TELEMETRY = "false";
    SCARF_NO_ANALYTICS = "true";
    DO_NOT_TRACK = "true";

    # Speedy first paint — skip the embedded HF model download for the
    # built-in semantic search; the user can enable it later if they
    # want vault-less RAG over uploaded docs.
    RAG_EMBEDDING_ENGINE = "";
  };
in
{
  options.local.openWebUI = {
    enable = mkEnableOption "Open WebUI chat frontend for local vLLM";

    package = mkOption {
      type = types.package;
      default = pkgs.open-webui;
      defaultText = literalExpression "pkgs.open-webui";
      description = "open-webui derivation to run.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Defaults to all interfaces so the LAN can reach the
        UI. Set to `127.0.0.1` if you put a reverse proxy in front for
        TLS / auth.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "HTTP port for the Open WebUI server.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — Open WebUI
        ships without TLS and the first-user-becomes-admin signup model
        means a LAN attacker can claim the instance if it's exposed
        before you've created an account.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = ''
        Directory holding the SQLite DB, uploaded files, vector store,
        and per-user settings. Back this up if you care about chat
        history and shared prompts.
      '';
    };

    openaiBaseURLs = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = literalExpression ''[ "http://127.0.0.1:8000/v1" ]'';
      description = ''
        OpenAI-compatible backend URLs. Default `null` means: derive
        them automatically from every entry in `local.vllm.services`.
        Set explicitly to override (e.g. to add a remote OpenAI proxy
        alongside the local vllm).
      '';
    };

    apiKey = mkOption {
      type = types.str;
      default = "none";
      description = ''
        API key sent to every upstream. vLLM ignores it but Open WebUI
        requires the env var be non-empty. The literal `none` is the
        Open WebUI convention for unauthenticated upstreams.
      '';
    };

    signupEnabled = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Allow new users to sign up via the UI. Leave on for the first
        boot (first signup becomes admin), then flip to false to seal
        the instance.
      '';
    };

    requireAuth = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Require a logged-in user to access the UI. Set false only for a
        single-user box behind a trusted network — Open WebUI without
        auth is essentially a public REST proxy to the upstream model.
      '';
    };

    defaultUserRole = mkOption {
      type = types.enum [
        "pending"
        "user"
        "admin"
      ];
      default = "pending";
      description = ''
        Role assigned to new signups after the first (which is always
        admin). `pending` means the admin must approve them — sane
        default for a household instance.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra env vars merged into Open WebUI's environment. Anything
        from the Open WebUI docs (https://docs.openwebui.com/getting-started/env-configuration)
        is fair game.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Sanity: starting Open WebUI without any backend means the model
    # picker sits empty and every chat fails. Warn loudly.
    assertions = [
      {
        assertion = (length endpoints) > 0;
        message = ''
          local.openWebUI.enable = true but no backends are configured:
          either enable `local.vllm.services` or set
          `local.openWebUI.openaiBaseURLs` explicitly.
        '';
      }
    ];

    services.open-webui = {
      enable = true;
      package = cfg.package;
      host = cfg.host;
      port = cfg.port;
      stateDir = cfg.stateDir;
      openFirewall = cfg.openFirewall;
      environment = baseEnvironment // cfg.extraEnvironment;
    };
  };
}
