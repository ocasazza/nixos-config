# bifrost — local LLM gateway (per-Mac launchd user agent).
#
# Renders ~/.bifrost/config.json from a Nix-typed options surface and runs
# the bifrost-http binary as `ai.bifrost.gateway`. A second launchd agent
# (`ai.bifrost.gcloud-token-refresh`) keeps the Google ADC access token
# fresh so bifrost can talk to vertex-proxy and Gemini without manual
# `gcloud auth print-access-token` invocations.
#
# Snowfall auto-discovers this module from modules/darwin/bifrost/.
{
  config,
  lib,
  pkgs,
  user ? lib.salt.user,
  ...
}:

with lib;

let
  cfg = config.local.bifrost;

  configDirAbs = "/Users/${user.name}${
    if cfg.configSubdir == "" then "" else "/" + cfg.configSubdir
  }";
  logDir = "/Users/${user.name}/.local/state/bifrost";

  # Render bifrost's config.json from the enabled provider blocks. Each
  # entry uses `env.<NAME>` as the value, which bifrost expands at request
  # time using its launchd EnvironmentVariables (set below).
  bifrostConfig = {
    "$schema" = "https://www.getbifrost.ai/schema";
    providers =
      lib.optionalAttrs cfg.providers.azure.enable {
        azure = {
          keys = [
            {
              name = "main";
              value = "env.AZURE_API_KEY";
              weight = 1;
              models = [ "*" ];
            }
          ];
          azure_config = {
            resource_name = cfg.providers.azure.resourceName;
            # Azure deployments are keyed by deployment id (case-sensitive).
            deployments = {
              "${cfg.providers.azure.deployment}" = { };
            };
          };
        };
      }
      // lib.optionalAttrs cfg.providers.litellm.enable {
        # LiteLLM as a custom OpenAI-compatible upstream. Routes ALL local
        # model groups (pdx-nxst-003 vLLM, exo MLX, embedding, etc.) that
        # LiteLLM already federates.
        litellm = {
          custom_provider_config = {
            base_provider_type = "openai";
            is_key_less = false;
          };
          keys = [
            {
              name = "main";
              value = "env.LITELLM_API_KEY";
              weight = 1;
              models = [ "*" ];
            }
          ];
          network_config = {
            base_url = "${cfg.providers.litellm.endpoint}/v1";
            default_request_timeout_in_seconds = 300;
          };
        };
      }
      // lib.optionalAttrs cfg.providers.vertexProxy.enable {
        # Schrodinger Vertex proxy (Anthropic-via-Vertex). gcloud ADC
        # access token from the refresh helper. Bifrost retries on 401
        # so a stale token gets re-tried after the next refresh.
        vertex-proxy = {
          custom_provider_config = {
            base_provider_type = "anthropic";
            is_key_less = false;
          };
          keys = [
            {
              name = "main";
              value = "env.GCLOUD_ACCESS_TOKEN";
              weight = 1;
              models = [ "*" ];
            }
          ];
          network_config = {
            base_url = cfg.providers.vertexProxy.endpoint;
            default_request_timeout_in_seconds = 300;
          };
        };
      }
      // lib.optionalAttrs cfg.providers.geminiVertex.enable {
        # Gemini access via Vertex AI using the same gcloud ADC token.
        # Replaces the gemini-cli OAuth flow with a unified Google auth.
        # Models: gemini-2.5-pro, gemini-2.5-flash, etc.
        vertex = {
          keys = [
            {
              name = "main";
              value = "env.GCLOUD_ACCESS_TOKEN";
              weight = 1;
              models = [ "*" ];
            }
          ];
          vertex_config = {
            project_id = cfg.providers.geminiVertex.projectId;
            region = cfg.providers.geminiVertex.region;
          };
        };
      };
  };

  configJson = (pkgs.formats.json { }).generate "bifrost-config.json" bifrostConfig;
in
{
  options.local.bifrost = {
    enable = mkEnableOption "Bifrost local LLM gateway (launchd user agent)";

    package = mkOption {
      type = types.package;
      default = pkgs.bifrost;
      defaultText = literalExpression "pkgs.bifrost";
      description = "The bifrost-http package (built from packages/bifrost).";
    };

    port = mkOption {
      type = types.port;
      default = lib.salt.ai.providers.bifrost.port;
      description = "TCP port bifrost binds on localhost.";
    };

    configSubdir = mkOption {
      type = types.str;
      default = ".bifrost";
      description = "Subdirectory of $HOME for bifrost's config + state.";
    };

    logLevel = mkOption {
      type = types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
    };

    providers = {
      azure = {
        enable = mkEnableOption "Azure OpenAI (Schrodinger) upstream";
        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Sops-decrypted path to the Azure API key (KEY=value or scalar).";
        };
        resourceName = mkOption {
          type = types.str;
          default = lib.salt.ai.providers.azure.resourceName;
        };
        deployment = mkOption {
          type = types.str;
          default = lib.salt.ai.providers.azure.deployment;
        };
      };

      litellm = {
        enable = mkEnableOption "LiteLLM (pdx-nxst-001) as OpenAI-compatible upstream";
        endpoint = mkOption {
          type = types.str;
          # lib.salt.ai (static) has caddyEndpoint; config.local.ai (runtime
          # subset) only has `endpoint`. Use the static one for default.
          default = lib.salt.ai.providers.litellm.caddyEndpoint;
          description = "Base URL of the LiteLLM proxy (without trailing /v1).";
        };
        apiKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Sops-decrypted path to the LiteLLM virtual key.";
        };
      };

      vertexProxy = {
        enable = mkEnableOption "Schrodinger Vertex proxy (Anthropic via gcloud id-token)";
        endpoint = mkOption {
          type = types.str;
          default = lib.salt.ai.providers.vertex.proxyEndpoint;
        };
      };

      geminiVertex = {
        enable = mkEnableOption "Gemini access via Vertex AI (using gcloud ADC token)";
        projectId = mkOption {
          type = types.str;
          # Default mirrors config.local.ai.providers.gemini.projectId default
          # in modules/darwin/ai/default.nix; not pulled from lib.salt.ai
          # (which doesn't expose the gemini provider block — only model names).
          default = "gemini-enterprise-495018";
        };
        region = mkOption {
          type = types.str;
          default = "us-central1";
          description = "Vertex AI region for Gemini calls. us-central1 has the broadest model availability.";
        };
      };
    };

    gcloudTokenRefresh = {
      intervalSec = mkOption {
        type = types.int;
        default = 3000;
        description = "How often (seconds) to refresh the Google ADC access token. Tokens expire in 1h; default is 50 min.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Render config.json into the project state dir at activation. We use
    # an activation script (not home.file.<path>) because the config dir
    # also stores runtime state that bifrost writes (logs, secrets/) so
    # it can't live in /nix/store as a symlink target.
    home-manager.users.${user.name} =
      { lib, ... }:
      {
        home.activation.bifrostConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p ${configDirAbs} ${configDirAbs}/secrets ${logDir}
          $DRY_RUN_CMD chmod 700 ${configDirAbs}/secrets
          $DRY_RUN_CMD install -m 0600 ${configJson} ${configDirAbs}/config.json
        '';
      };

    # launchd: bifrost gateway. Reads provider API keys from env vars
    # populated below (each derived from sops-decrypted secret files via
    # `launchctl setenv`-style indirection — actually just $(cat <file>)
    # in the wrapping shell, since launchd plists don't support that).
    launchd.user.agents."ai.bifrost.gateway" = {
      serviceConfig = {
        Label = "ai.bifrost.gateway";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-lc"
          ''
            ${lib.optionalString cfg.providers.azure.enable ''
              if [ -r "${toString cfg.providers.azure.apiKeyFile}" ]; then
                export AZURE_API_KEY="$(cut -d= -f2- < "${toString cfg.providers.azure.apiKeyFile}")"
              fi
            ''}
            ${lib.optionalString cfg.providers.litellm.enable ''
              if [ -r "${toString cfg.providers.litellm.apiKeyFile}" ]; then
                export LITELLM_API_KEY="$(cut -d= -f2- < "${toString cfg.providers.litellm.apiKeyFile}")"
              fi
            ''}
            ${lib.optionalString (cfg.providers.vertexProxy.enable || cfg.providers.geminiVertex.enable) ''
              if [ -r "${configDirAbs}/secrets/gcloud-access-token" ]; then
                export GCLOUD_ACCESS_TOKEN="$(cat "${configDirAbs}/secrets/gcloud-access-token")"
              fi
            ''}
            exec ${cfg.package}/bin/bifrost-http \
              -host localhost \
              -port ${toString cfg.port} \
              -app-dir ${configDirAbs} \
              -log-level ${cfg.logLevel} \
              -log-style pretty
          ''
        ];
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        RunAtLoad = true;
        StandardOutPath = "${logDir}/gateway.log";
        StandardErrorPath = "${logDir}/gateway.err";
        EnvironmentVariables = {
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin";
          HOME = "/Users/${user.name}";
        };
      };
    };

    # launchd: gcloud token refresh helper. Runs every intervalSec,
    # refreshes the ADC token, kicks bifrost to re-read it.
    launchd.user.agents."ai.bifrost.gcloud-token-refresh" =
      mkIf (cfg.providers.vertexProxy.enable || cfg.providers.geminiVertex.enable)
        {
          serviceConfig = {
            Label = "ai.bifrost.gcloud-token-refresh";
            ProgramArguments = [
              "${pkgs.bash}/bin/bash"
              "${./refresh-gcloud-token.sh}"
              configDirAbs
            ];
            # Run at load (so bifrost has a token immediately after switch),
            # then every cfg.gcloudTokenRefresh.intervalSec seconds.
            RunAtLoad = true;
            StartInterval = cfg.gcloudTokenRefresh.intervalSec;
            StandardOutPath = "${logDir}/token-refresh.log";
            StandardErrorPath = "${logDir}/token-refresh.err";
            EnvironmentVariables = {
              # gcloud needs PATH to find python and itself.
              PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin:/Users/${user.name}/google-cloud-sdk/bin";
              HOME = "/Users/${user.name}";
            };
          };
        };
  };
}
