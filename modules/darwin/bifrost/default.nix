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
  # vertex-proxy.sdgr.app/v1 has /v1 as the message endpoint root. Bifrost's
  # anthropic provider appends /v1/messages itself, so we need the bare host.
  vertexProxyBaseURL = lib.removeSuffix "/v1" cfg.providers.vertexProxy.endpoint;

  bifrostConfig = {
    "$schema" = "https://www.getbifrost.ai/schema";
    # Disable the config persistence store so bifrost is purely driven by
    # config.json on each start. Without this, bifrost remembers providers
    # in ~/.bifrost/config.db across restarts and we end up with phantom
    # entries (e.g. an auto-bootstrapped openai key from a prior run).
    config_store.enabled = false;
    logs_store.enabled = false;
    providers =
      # azure: Azure-specific config goes in `azure_key_config` PER KEY
      # (per `core/schemas/account.go:Key.AzureKeyConfig`). The endpoint
      # is the resource base URL — bifrost composes the deployment path.
      lib.optionalAttrs cfg.providers.azure.enable {
        azure = {
          keys = [
            {
              name = "main";
              value = "env.AZURE_API_KEY";
              weight = 1;
              models = [ "*" ];
              azure_key_config = {
                endpoint = "https://${cfg.providers.azure.resourceName}.openai.azure.com";
                # api_version defaults to 2024-10-21 (matches what opencode
                # was using), so we omit it here.
              };
            }
          ];
        };
      }
      # litellm: custom OpenAI-compatible upstream. Routes the local-model
      # groups LiteLLM already federates (pdx-nxst-003 vLLM, exo MLX, etc.).
      // lib.optionalAttrs cfg.providers.litellm.enable {
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
            # base_url is the bare endpoint; bifrost's openai base type
            # appends /v1/<path> itself. Don't include /v1 here (caused
            # 404s like vertex-proxy did with /v1/v1/messages).
            base_url = cfg.providers.litellm.endpoint;
            default_request_timeout_in_seconds = 300;
          };
        };
      }
      # vertex-proxy: Schrodinger's Anthropic-on-Vertex passthrough. Custom
      # anthropic upstream. Bifrost appends /v1/messages itself, so base_url
      # is the bare host (vertexProxyBaseURL strips the /v1 suffix).
      #
      # The proxy doesn't expose `/v1/models` (it's a messages-only
      # passthrough), so bifrost's startup model-list call returns HTML/403.
      # That's harmless — POST /v1/messages still works. Bifrost will
      # silently flag the provider as "list_models_failed" but accept
      # routed chat completion requests.
      // lib.optionalAttrs cfg.providers.vertexProxy.enable {
        vertex-proxy = {
          custom_provider_config = {
            base_provider_type = "anthropic";
            is_key_less = false;
          };
          keys = [
            {
              name = "main";
              # vertex-proxy validates a Google IDENTITY token (JWT), not
              # an access token. Sourced from `gcloud auth print-identity-token`
              # by the refresh helper; written to ~/.bifrost/secrets/gcloud-id-token.
              value = "env.GCLOUD_ID_TOKEN";
              weight = 1;
              models = [ "*" ];
            }
          ];
          network_config = {
            base_url = vertexProxyBaseURL;
            default_request_timeout_in_seconds = 300;
          };
        };
      }
      # vertex (Google Vertex AI): native bifrost provider for Gemini access
      # using gcloud ADC. Per-key config holds project_id / project_number /
      # region. AuthCredentials="" tells bifrost to use the access token from
      # the `value` field directly (instead of a service-account JSON file).
      // lib.optionalAttrs cfg.providers.geminiVertex.enable {
        vertex = {
          keys = [
            {
              # Bifrost's vertex provider uses Google's ADC chain via
              # `google.FindDefaultCredentials` (see core/providers/vertex/
              # vertex.go:getAuthTokenSource). The Key.Value field is NOT
              # used for vertex auth. Empty value avoids being mistaken
              # for an API key in API-key flows.
              name = "main";
              value = "";
              weight = 1;
              models = [ "*" ];
              vertex_key_config = {
                project_id = cfg.providers.geminiVertex.projectId;
                project_number = cfg.providers.geminiVertex.projectNumber;
                region = cfg.providers.geminiVertex.region;
                # Empty auth_credentials triggers ADC discovery from
                # ~/.config/gcloud/application_default_credentials.json
                # (per account.go NOTE). User must have run
                # `gcloud auth application-default login` once.
                auth_credentials = "";
              };
            }
          ];
          # Defense-in-depth: set x-goog-user-project so the ADC token's
          # quota project is unambiguous (the user also ran
          # `gcloud auth application-default set-quota-project <id>`).
          network_config = {
            extra_headers = {
              "x-goog-user-project" = cfg.providers.geminiVertex.projectId;
            };
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
        projectNumber = mkOption {
          type = types.str;
          # Numeric project number for the GCP project, required by bifrost's
          # vertex_key_config. Get with: `gcloud projects describe <id> --format='value(projectNumber)'`.
          default = "901456275242";
          description = "Numeric GCP project number (different from projectId).";
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
          # Wipe bifrost's persistent config_store DB so phantom providers
          # from prior runs don't shadow what's in config.json. The
          # `config_store.enabled = false` flag in config.json should
          # prevent these from ever being written, but be defensive.
          $DRY_RUN_CMD rm -f ${configDirAbs}/config.db ${configDirAbs}/config.db-shm ${configDirAbs}/config.db-wal
          $DRY_RUN_CMD rm -f ${configDirAbs}/logs.db ${configDirAbs}/logs.db-shm ${configDirAbs}/logs.db-wal
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
            ${lib.optionalString cfg.providers.geminiVertex.enable ''
              if [ -r "${configDirAbs}/secrets/gcloud-access-token" ]; then
                export GCLOUD_ACCESS_TOKEN="$(cat "${configDirAbs}/secrets/gcloud-access-token")"
              fi
            ''}
            ${lib.optionalString cfg.providers.vertexProxy.enable ''
              if [ -r "${configDirAbs}/secrets/gcloud-id-token" ]; then
                export GCLOUD_ID_TOKEN="$(cat "${configDirAbs}/secrets/gcloud-id-token")"
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
