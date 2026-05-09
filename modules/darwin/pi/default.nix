# pi — Pi Coding Agent harness (mirrors gemini-cli/claude-code modules).
#
# Pi is a TypeScript-based terminal coding harness with native extension
# support. The agentic-stack repo has a pi adapter that ships
# .pi/extensions/memory-hook.ts to log tool calls to episodic memory and
# fire auto_dream on shutdown — this module wires that adapter via Nix.
#
# Provider: routes through the local bifrost gateway (single endpoint for
# all cloud providers + LiteLLM upstream).
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
      default = lib.salt.ai.providers.bifrost.endpoint;
      description = "OpenAI-compatible endpoint pi sends requests to. Defaults to local bifrost.";
    };

    defaultModel = mkOption {
      type = types.str;
      default = "azure/${lib.salt.ai.providers.azure.deployment}";
      description = ''
        Default model id pi uses when none specified. Format follows
        bifrost's `<provider>/<model>` route key (e.g. `azure/Kimi-K2.6`,
        `vertex/gemini-2.5-pro`, `litellm/pdx-nxst-003-qwen3.6-35b-a3b`).
      '';
    };

    installAgenticHook = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Copy the .pi/extensions/memory-hook.ts file from the agentic-stack
        fork's pi adapter into ~/.pi/extensions/. The extension subscribes
        to pi's tool_result event and logs to .agent/memory/episodic, then
        fires auto_dream.py on session shutdown.
      '';
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${user.name} =
      hmArgs:
      let
        hmConfig = hmArgs.config;
        hmLib = hmArgs.lib;
      in
      {
        # Required runtime deps. pi itself is npm-installed (not in nixpkgs)
        # but it needs node + npm on PATH; bun is also useful for running
        # extensions. Both are already present via opencode wiring; declare
        # idempotently in case opencode is later disabled.
        home.packages = with pkgs; [
          nodejs_22
        ];

        # Activation: install pi globally if missing. Same pattern as opencode's
        # bun install: only re-run when needed (the npm registry version check
        # handles upgrades on demand via `npm i -g <pkg>`).
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

        # Pi's user config. Provider points at bifrost; pi sends OpenAI-format
        # requests there. The empty apiKey is required by the schema but
        # ignored by bifrost's no-auth localhost mode.
        home.file.".pi/config.json".source = (pkgs.formats.json { }).generate "pi-config.json" {
          providers = {
            default = {
              type = "openai";
              baseURL = cfg.providerEndpoint;
              apiKey = "no-auth";
            };
          };
          defaultModel = cfg.defaultModel;
          # Don't pollute user's project dirs with pi's runtime state.
          stateDir = "/Users/${user.name}/.pi/state";
        };

        # Memory-hook extension from agentic-stack's pi adapter. Logs
        # bash/edit/write tool results to .agent/memory/episodic and runs
        # auto_dream on session shutdown — the pi-side equivalent of
        # claude-code's PostToolUse + Stop hooks.
        home.file.".pi/extensions/memory-hook.ts" = mkIf cfg.installAgenticHook {
          source = "${hmConfig.programs.agentic-stack.package}/share/agentic-stack/adapters/pi/.pi/extensions/memory-hook.ts";
        };

        # Skills: symlink to the merged agentic-stack skills directory so pi
        # sees the same skill set as Claude Code (~/.claude/skills points at
        # the same merged dir).
        home.file.".pi/skills" = {
          source = hmConfig.programs.agentic-stack.skills.effectiveDir;
        };
      };
  };
}
