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
      description = "Settings to write to ~/.claude/settings.json";
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
    ]
    ++ lib.optionals cfg.vertex.enable [ pkgs.google-cloud-sdk ];

    # Generate settings.json and API key helper via activation script
    system.activationScripts.claudeCode.text =
      let
        user = lib.salt.user;
        settingsWithModel = cfg.settings // {
          model = cfg.model;
        };
        settingsJson = builtins.toJSON settingsWithModel;
      in
      ''
        echo "setting up Claude Code..." >&2
        mkdir -p /Users/${user.name}/.claude
        cat > /Users/${user.name}/.claude/settings.json << 'SETTINGS'
        ${settingsJson}
        SETTINGS
        chown -R ${user.name} /Users/${user.name}/.claude
      ''
      + lib.optionalString cfg.apiKeyHelper ''
        cat > /Users/${user.name}/.claude/get-iam-token.sh << 'TOKENHELPER'
        #!/usr/bin/env bash
        set -euo pipefail
        echo $(gcloud auth print-identity-token 2>/dev/null)
        TOKENHELPER
        chmod +x /Users/${user.name}/.claude/get-iam-token.sh
      '';

    # Load gcloud credentials for Vertex AI
    programs.zsh.shellInit = lib.mkIf cfg.vertex.enable ''
      if command -v gcloud >/dev/null 2>&1; then
        export GOOGLE_APPLICATION_CREDENTIALS_JSON="$(gcloud auth print-access-token 2>/dev/null || echo "")"
      fi
    '';
  };
}
