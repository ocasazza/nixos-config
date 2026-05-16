# Unified AI Infrastructure Module: centralize provider config, secrets, and environment.
#
# This module defines the "Source of Truth" for all AI providers used by
# clients in this repository (Hermes, OpenCode, Claude Code, Zed).
{
  config,
  lib,
  user ? lib.salt.user,
  ...
}:

with lib;

let
  cfg = config.local.ai;
in
{
  options.local.ai = {
    enable = mkEnableOption "Unified AI infrastructure";

    providers = {
      litellm = {
        enable = mkEnableOption "LiteLLM federated proxy (pdx-nxst-003)";
        endpoint = mkOption {
          type = types.str;
          default = "http://pdx-nxst-001.schrodinger.com:8080/litellm";
          description = "LiteLLM Caddy-fronted endpoint.";
        };
        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Sops-decrypted path to the LiteLLM virtual key.";
        };
      };

      vertex = {
        enable = mkEnableOption "Google Cloud Vertex AI";
        projectId = mkOption {
          type = types.str;
          default = "vertex-code-454718";
          description = "GCP Project ID for Vertex AI (Claude Code, etc.).";
        };
        region = mkOption {
          type = types.str;
          default = "us-east5";
          description = "GCP Region for Vertex AI.";
        };
        proxyEndpoint = mkOption {
          type = types.str;
          default = "https://vertex-proxy.sdgr.app/v1";
          description = "Schrodinger Vertex Proxy endpoint.";
        };
      };

      gemini = {
        enable = mkEnableOption "Google Gemini (Personal/Enterprise)";
        projectId = mkOption {
          type = types.str;
          default = "gemini-enterprise-495018";
          description = "GCP Project ID for Gemini CLI.";
        };
        location = mkOption {
          type = types.str;
          default = "global";
          description = "GCP Location for Gemini CLI.";
        };
      };

      azure = {
        enable = mkEnableOption "Schrodinger Azure OpenAI";
        resourceName = mkOption {
          type = types.str;
          default = "schrodinger-code";
        };
        deployment = mkOption {
          type = types.str;
          default = "Kimi-K2.6";
        };
        endpoint = mkOption {
          type = types.str;
          default = "https://schrodinger-code.openai.azure.com/openai/deployments/Kimi-K2.6";
        };
        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
        };
      };

    };

    # Standard model mappings
    models = {
      claudeSonnet = mkOption {
        type = types.str;
        default = "claude-sonnet-4-7";
      };
      geminiPro = mkOption {
        type = types.str;
        default = "gemini-3-pro";
      };
      defaultLocal = mkOption {
        type = types.str;
        default = "qwen3.6-35b-a3b";
      };
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${user.name}.home = {
      # Static provider env
      sessionVariables = {
        GOOGLE_VERTEX_PROJECT = cfg.providers.vertex.projectId;
        GOOGLE_VERTEX_LOCATION = cfg.providers.vertex.region;
        GOOGLE_CLOUD_PROJECT = cfg.providers.gemini.projectId;
        GOOGLE_CLOUD_LOCATION = cfg.providers.gemini.location;
        AZURE_RESOURCE_NAME = cfg.providers.azure.resourceName;
        # Placeholder so the Anthropic SDK doesn't refuse to initialize.
        # Not used for actual auth — Vertex Claude is available via the
        # LiteLLM /vertex passthrough (auth: false, clients bring own
        # gcloud id-token).
        ANTHROPIC_API_KEY = "vertex-proxy-uses-gcloud-identity-token";
      };

      # Secret-based env (sourced at shell init)
      sessionVariablesExtra = mkAfter ''
        # Unified AI Provider Secret Environment
        ${optionalString (cfg.providers.litellm.enable && cfg.providers.litellm.apiKeyFile != null) ''
          if [ -r "${toString cfg.providers.litellm.apiKeyFile}" ]; then
            export LITELLM_API_KEY="$(cut -d= -f2- < "${toString cfg.providers.litellm.apiKeyFile}")"
            # Compatibility alias for hermes
            export LITELLM_HERMES_API_KEY="$LITELLM_API_KEY"
          fi
        ''}

        ${optionalString (cfg.providers.azure.enable && cfg.providers.azure.apiKeyFile != null) ''
          if [ -r "${toString cfg.providers.azure.apiKeyFile}" ]; then
            export AZURE_API_KEY="$(cut -d= -f2- < "${toString cfg.providers.azure.apiKeyFile}")"
          fi
        ''}
      '';
    };
  };
}
