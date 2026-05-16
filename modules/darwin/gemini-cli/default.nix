# Gemini CLI configuration: support for Vertex AI, Google Sign-in (OAuth), and API Keys.
#
# Snowfall auto-discovers this module from modules/darwin/gemini-cli/.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.gemini-cli;
  user = lib.salt.user;
in
{
  options.programs.gemini-cli = {
    enable = lib.mkEnableOption "Gemini CLI configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeShellScriptBin "gemini" ''
        export GEMINI_CLI_TRUST_WORKSPACE=true
        export NODE_NO_WARNINGS=1
        exec ${pkgs.gemini-cli-bin}/bin/gemini "$@"
      '';
      description = "The gemini-cli package to use.";
    };

    authType = lib.mkOption {
      type = lib.types.enum [
        "vertex-ai"
        "oauth-personal"
        "api-key"
      ];
      default = "vertex-ai";
      description = ''
        Authentication method to use:
        * `vertex-ai`: Google Cloud Vertex AI (uses ADC or Service Account).
        * `oauth-personal`: Standard Google Account sign-in (Sign in with Google).
        * `api-key`: Gemini API key from AI Studio.
      '';
    };

    vertex = {
      projectId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Google Cloud project ID for Vertex AI.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Google Cloud region for Vertex AI.";
      };
    };

    telemetry = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Gemini telemetry.";
      };
    };

    sandbox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Gemini sandbox.";
      };
    };

    seatbeltProfile = lib.mkOption {
      type = lib.types.str;
      default = "permissive-open";
      description = "Seatbelt profile for Gemini.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Sops-decrypted path to the Gemini API key.";
    };

    serviceAccountKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional path to a sops-managed service account JSON key file.";
    };

    googleAccountsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional path to a sops-managed google_accounts.json file.";
    };

    oauthCredsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional path to a sops-managed oauth_creds.json file.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra fields merged into ~/.gemini/settings.json on top of the
        managed `security.auth` block. Use for `ui.*`, `tools.*`,
        `seatbeltProfile`, `ide.*`, etc.
      '';
      example = lib.literalExpression ''
        {
          ui.errorVerbosity = "full";
          tools = {
            sandbox = "/path/to/custom-profile.sb";
            sandboxAllowedPaths = [ "/path/to/repo" ];
          };
          seatbeltProfile = "custom";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    home-manager.users.${user.name} = {
      # Environment variables for gemini-cli.
      # Unified variables are now handled by modules/darwin/ai.
      home.sessionVariablesExtra = ''
        export GEMINI_TELEMETRY_ENABLED="${if cfg.telemetry.enable then "true" else "false"}"
        export GEMINI_SANDBOX="${if cfg.sandbox.enable then "true" else "false"}"
        export SEATBELT_PROFILE="${cfg.seatbeltProfile}"
        ${lib.optionalString (cfg.authType == "vertex-ai") "export GOOGLE_GENAI_USE_VERTEXAI=\"true\""}
        ${lib.optionalString (
          cfg.authType == "vertex-ai" && cfg.serviceAccountKeyFile != null
        ) "export GOOGLE_APPLICATION_CREDENTIALS=\"${toString cfg.serviceAccountKeyFile}\""}
        ${lib.optionalString (cfg.authType == "api-key" && cfg.apiKeyFile != null) ''
          if [ -r "${toString cfg.apiKeyFile}" ]; then
            export GEMINI_API_KEY="$(cat "${toString cfg.apiKeyFile}")"
          fi
        ''}
      '';

      # Managed settings.json: select the desired auth type, vertex config if provided,
      # plus any caller-supplied extras (ui, tools, seatbeltProfile, ide.*).
      home.file.".gemini/settings.json".source = (pkgs.formats.json { }).generate "gemini-settings.json" (
        lib.recursiveUpdate {
          security.auth.selectedType = cfg.authType;
          vertex = lib.optionalAttrs (cfg.vertex.projectId != "") {
            projectId = cfg.vertex.projectId;
            region = cfg.vertex.region;
          };
        } cfg.extraSettings
      );

      # Optional credentials files from sops
      home.file.".gemini/google_accounts.json" = lib.mkIf (cfg.googleAccountsFile != null) {
        source = cfg.googleAccountsFile;
      };

      home.file.".gemini/oauth_creds.json" = lib.mkIf (cfg.oauthCredsFile != null) {
        source = cfg.oauthCredsFile;
      };
    };
  };
}
