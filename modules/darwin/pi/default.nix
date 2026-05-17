# pi — Pi Coding Agent harness (mirrors gemini-cli/claude-code modules).
#
# Pi is a TypeScript-based terminal coding harness with native extension
# support. Provider: routes through LiteLLM for local model access.
#
# Pi is NOT in nixpkgs as a Nix derivation; we install it via npm-global
# at activation time (same pattern as opencode's `bun install`).
{
  config,
  lib,
  pkgs,
  user ? lib.salt.user,
  ...
}:

with lib;

let
  cfg = config.programs.pi;
in
{
  options.programs.pi = {
    enable = mkEnableOption "Pi Coding Agent (CLI harness, npm-installed)";

    npmPackage = mkOption {
      type = types.str;
      default = "@mariozechner/pi-coding-agent";
      description = "npm package name installed globally at activation.";
    };

    providerEndpoint = mkOption {
      type = types.str;
      default = "${lib.salt.ai.providers.litellm.caddyEndpoint}/v1";
      description = "OpenAI-compatible endpoint pi sends requests to. Defaults to LiteLLM.";
    };

    defaultModel = mkOption {
      type = types.str;
      default = lib.salt.ai.providers.litellm.defaultLocalGroup;
      description = "Default model id pi uses when none specified.";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${user.name} =
      hmArgs:
      let
        hmLib = hmArgs.lib;
      in
      {
        home.packages = with pkgs; [
          nodejs_22
        ];

        home.activation.installPi = hmLib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if command -v npm >/dev/null 2>&1; then
            if ! command -v pi >/dev/null 2>&1; then
              echo "pi: installing ${cfg.npmPackage} globally via npm..."
              $DRY_RUN_CMD npm install -g ${cfg.npmPackage} || \
                echo "warning: npm install failed; install pi manually with: npm i -g ${cfg.npmPackage}" >&2
            fi
          else
            echo "warning: npm not on PATH; skipping pi install. Add nodejs_22 to home.packages." >&2
          fi
        '';

        home.file.".pi/config.json".source = (pkgs.formats.json { }).generate "pi-config.json" {
          providers = {
            default = {
              type = "openai";
              baseURL = cfg.providerEndpoint;
              apiKey = "no-auth";
            };
          };
          defaultModel = cfg.defaultModel;
          stateDir = "${config.users.users.${user.name}.home}/.pi/state";
        };

        home.file.".pi/skills" = {
          source = config.local.skills.path;
        };
      };
  };
}
