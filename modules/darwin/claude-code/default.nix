{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-code;
  user = lib.salt.user;

  useLegacyVertex = cfg.vertex.enable && !cfg.litellm.enable;

  vertexProjectIdResolved =
    if cfg.vertex.projectId != "" then cfg.vertex.projectId else "vertex-code-454718";
  vertexRegionResolved = if cfg.vertex.region != "" then cfg.vertex.region else "us-east5";

  # All env vars land in settings.json#env — Claude Code exports them
  # before forking subprocesses, so wrapper-level injection is not needed.
  settingsEnv =
    if cfg.litellm.enable then
      (
        if cfg.litellm.cloudPassthrough then
          {
            ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/vertex/v1";
            CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
            CLAUDE_CODE_USE_VERTEX = "1";
            CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
            ANTHROPIC_VERTEX_PROJECT_ID = vertexProjectIdResolved;
            CLOUD_ML_REGION = vertexRegionResolved;
          }
        else
          {
            ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/v1";
          }
      )
    else if cfg.vertex.enable then
      {
        CLAUDE_CODE_USE_VERTEX = "1";
        CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
        CLOUD_ML_REGION = cfg.vertex.region;
        ANTHROPIC_VERTEX_PROJECT_ID = cfg.vertex.projectId;
        ANTHROPIC_VERTEX_BASE_URL = cfg.vertex.baseURL;
        CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
      }
    else
      { };

  helperActive =
    cfg.apiKeyHelper || (cfg.litellm.enable && cfg.litellm.cloudPassthrough) || useLegacyVertex;

  settingsWithModel =
    cfg.settings
    // {
      model = cfg.model;
      env = (cfg.settings.env or { }) // settingsEnv // cfg.environment;
    }
    // lib.optionalAttrs helperActive {
      apiKeyHelper = "~/.claude/get-iam-token.sh";
    };

  telemetryEnv = lib.optionalAttrs cfg.telemetry.enable {
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = cfg.telemetry.protocol;
    OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.endpoint;
    OTEL_METRIC_EXPORT_INTERVAL = toString cfg.telemetry.exportIntervalMs;
    OTEL_RESOURCE_ATTRIBUTES = "service.namespace=claude-code,host.name=${
      config.networking.hostName or "darwin"
    }";
  };

  # OTel env vars must be present in the process environment before the
  # OTel SDK initialises, which happens before Claude reads settings.json.
  # We keep these on a thin shell wrapper rather than in settings.json#env.
  needsTelemetryWrapper = cfg.telemetry.enable;

  claudePackage =
    if needsTelemetryWrapper then
      pkgs.symlinkJoin {
        name = "claude-code-otel-${cfg.package.version}";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeShellWrapper ];
        postBuild =
          let
            setFlags = lib.concatStringsSep " " (
              lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") telemetryEnv
            );
          in
          ''
            wrapProgram $out/bin/claude ${setFlags}
          '';
      }
    else
      cfg.package;
in
{
  options.programs.claude-code = {
    enable = lib.mkEnableOption "Claude Code AI assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      description = "The claude-code package to use.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "claude-opus-4-7";
      description = "Default model to use.";
    };

    vertex = {
      enable = lib.mkEnableOption "Vertex AI proxy for Claude Code (legacy direct path; ignored when litellm.enable = true)";

      projectId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Google Cloud project ID for Vertex AI.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east5";
        description = "Google Cloud region for Vertex AI.";
      };

      baseURL = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Base URL for the Vertex AI proxy.";
      };
    };

    litellm = {
      enable = lib.mkEnableOption "Route Claude Code through LiteLLM";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://desk-nxst-001:4000";
        description = "LiteLLM base URL.";
      };

      virtualKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Sops-decrypted path to this client's LiteLLM virtual key (KEY=VALUE).";
      };

      cloudPassthrough = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Route cloud calls through LiteLLM's /vertex/* passthrough.";
      };

      defaultGroup = lib.mkOption {
        type = lib.types.str;
        default = "coder-cloud-claude";
        description = "Default LiteLLM model-group for this client.";
      };

      allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "coder-local"
          "coder-remote"
          "coder-cloud-claude"
          "embedding"
        ];
        description = "Informational: model-groups this client may reference.";
      };
    };

    apiKeyHelper = lib.mkEnableOption "API key helper script for Vertex AI";

    telemetry = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Push OTel metrics + logs to a collector.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://desk-nxst-001:4317";
        description = "OTLP endpoint URL.";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "grpc"
          "http/protobuf"
        ];
        default = "grpc";
        description = "OTLP transport: gRPC (4317) or HTTP/protobuf (4318).";
      };

      exportIntervalMs = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = "Milliseconds between metric exports.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings to merge into ~/.claude/settings.json.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables added to settings.json#env.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.vertex.enable && cfg.litellm.enable);
        message = "programs.claude-code: vertex.enable and litellm.enable are mutually exclusive.";
      }
    ];

    environment.systemPackages = [
      claudePackage
    ]
    ++ lib.optionals (cfg.vertex.enable || (cfg.litellm.enable && cfg.litellm.cloudPassthrough)) [
      pkgs.google-cloud-sdk
    ];

    # Manage ~/.claude/ declaratively via home-manager.
    home-manager.users.${user.name} = {
      home.file.".claude/settings.json".text = builtins.toJSON settingsWithModel;

      home.file.".claude/get-iam-token.sh" = lib.mkIf helperActive {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo $(gcloud auth print-identity-token 2>/dev/null)
        '';
      };

      # When litellm + virtual key (not cloudPassthrough), read the sops
      # key at shell init and export it. The apiKeyHelper path doesn't
      # apply here — the key is static for the session.
      home.sessionVariablesExtra =
        lib.optionalString
          (cfg.litellm.enable && !cfg.litellm.cloudPassthrough && cfg.litellm.virtualKeyFile != null)
          ''
            if [ -r "${toString cfg.litellm.virtualKeyFile}" ]; then
              export ANTHROPIC_API_KEY="$(cut -d= -f2- < "${toString cfg.litellm.virtualKeyFile}")"
            fi
          '';
    };
  };
}
