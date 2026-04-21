{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-code;

  vertexEnvVars = lib.optionalAttrs cfg.vertex.enable {
    CLAUDE_CODE_USE_VERTEX = "1";
    CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
    ANTHROPIC_VERTEX_PROJECT_ID = cfg.vertex.projectId;
    ANTHROPIC_VERTEX_BASE_URL = cfg.vertex.baseURL;
    CLOUD_ML_REGION = cfg.vertex.region;
  };

  apiKeyEnvVars = lib.optionalAttrs cfg.apiKeyHelper {
    CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
  };

  # OTel pipeline → luna's collector. Same env-var contract as Anthropic's
  # monitoring guide (https://github.com/anthropics/claude-code-monitoring-guide):
  # CLAUDE_CODE_ENABLE_TELEMETRY=1 turns on emission, then standard OTLP
  # vars route metrics + logs to the configured endpoint. We also tag
  # service.namespace/host.name so multi-machine slicing works in Grafana.
  telemetryEnvVars = lib.optionalAttrs cfg.telemetry.enable {
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = cfg.telemetry.protocol;
    OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.endpoint;
    OTEL_METRIC_EXPORT_INTERVAL = toString cfg.telemetry.exportIntervalMs;
    OTEL_RESOURCE_ATTRIBUTES = "service.namespace=claude-code,host.name=${config.networking.hostName}";
  };

  allEnvVars = vertexEnvVars // apiKeyEnvVars // telemetryEnvVars // cfg.environment;

  wrappedClaude = pkgs.symlinkJoin {
    name = "claude-code-wrapped-${cfg.package.version}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild =
      let
        setFlags = lib.concatStringsSep " " (
          lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") (
            lib.filterAttrs (_: v: v != "") allEnvVars
          )
        );
      in
      ''
        wrapProgram $out/bin/claude ${setFlags}
      '';
  };
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
      enable = lib.mkEnableOption "Vertex AI proxy for Claude Code";

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

    apiKeyHelper = lib.mkEnableOption "API key helper script for Vertex AI";

    telemetry = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Push OTel metrics + logs to a collector. Default-on because the
          SDK silently drops OTLP when the endpoint is unreachable, so a
          laptop off the home LAN behaves identically to one on it. Set
          to false to suppress emission entirely.
        '';
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default =
          if (config.local.observability.enable or false) then
            "http://127.0.0.1:4317"
          else
            "http://luna.local:4317";
        defaultText = lib.literalExpression ''
          if config.local.observability.enable
          then "http://127.0.0.1:4317"
          else "http://luna.local:4317"
        '';
        description = ''
          OTLP endpoint URL. Auto-derived: if this host *is* the collector
          (local.observability.enable = true), defaults to loopback so
          metrics never traverse the network; otherwise defaults to luna's
          published endpoint on the home LAN. Override per-host if neither
          fits (e.g. an off-site box that should push to a tunnel).
        '';
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "grpc"
          "http/protobuf"
        ];
        default = "grpc";
        description = ''
          OTLP transport. gRPC (4317) is the default and what Anthropic's
          reference collector listens on; switch to `http/protobuf` (4318)
          if a network path can't speak HTTP/2.
        '';
      };

      exportIntervalMs = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = ''
          Milliseconds between metric exports. 10s is responsive without
          hammering the collector; bump to 60000 for laptops on cellular.
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings to write to /etc/claude-code/settings.json";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables to set on the claude wrapper.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      wrappedClaude
      pkgs.bubblewrap
      pkgs.socat
    ]
    ++ lib.optionals cfg.vertex.enable [ pkgs.google-cloud-sdk ];

    # System-wide settings
    environment.etc."claude-code/settings.json".text = builtins.toJSON (
      cfg.settings
      // {
        model = cfg.model;
      }
    );

    # API key helper via profile.d
    environment.etc."profile.d/claude-code.sh" = lib.mkIf cfg.vertex.enable {
      text = ''
        export CLAUDE_CODE_USE_VERTEX=1
        export CLAUDE_CODE_SKIP_VERTEX_AUTH=1
        export ANTHROPIC_VERTEX_PROJECT_ID="${cfg.vertex.projectId}"
        export ANTHROPIC_VERTEX_BASE_URL="${cfg.vertex.baseURL}"
        export CLOUD_ML_REGION="${cfg.vertex.region}"
      '';
    };
  };
}
