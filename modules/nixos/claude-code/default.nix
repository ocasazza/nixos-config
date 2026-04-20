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

  allEnvVars = vertexEnvVars // apiKeyEnvVars // cfg.environment;

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
