# agentic-stack: thin wrapper around the schrodinger-agentic-stack flake
# input. Imports the fork's home-manager module and supplies:
#   - provider config from `lib.salt.ai.providers.*`
#   - merged skills derivation (bundled + project-specific snowfall-lib)
#   - claude-code wiring with `bd prime` extra hooks
#
# The fork lives at `~/Repositories/schrodinger/schrodinger-agentic-stack/`
# and exposes:
#   - homeManagerModules.default → programs.agentic-stack.{enable, providers, skills, harnesses, autoDream, ...}
#   - packages.<system>.default  → 12 bin shims (agentic-recall, agentic-show, ...)
#   - lib.<system>.mergeSkills   → helper that builds a merged skills derivation
#
# The merged skills derivation is exposed back out to the system level via
# `local.agentic-stack.mergedSkills` so `local.hermes.extraSkillsDir` can
# read the same value.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  user = lib.salt.user;

  forkLib = inputs.schrodinger-agentic-stack.lib.${pkgs.stdenv.hostPlatform.system};

  # Project-specific skills layered on top of the fork's bundled set.
  # snowfall-lib lives here (not in the fork) because it's specific to
  # snowfall-lib-based Nix flakes — not every consumer of the fork uses it.
  mergedSkills = forkLib.mergeSkills {
    extras = {
      snowfall-lib = {
        src = ./skills/snowfall-lib;
        manifest = {
          name = "snowfall-lib";
          version = "2026-05-09";
          triggers = [
            "snowfall"
            "mkFlake"
            "add module"
            "add package"
            "add system"
            "add home"
            "add overlay"
            "add shell"
            "add check"
            "add template"
            "add library"
            "snowfall-lib"
          ];
          tools = [
            "bash"
            "read"
          ];
          preconditions = [ "flake.nix uses snowfall-lib input" ];
          constraints = [
            "preserve existing snowfall.namespace"
            "files must be default.nix"
            "new files must be git tracked"
          ];
          category = "infrastructure";
        };
        indexEntry = ''
          ## snowfall-lib
          Project-specific. Loads when adding/moving Nix flake components in
          projects that use snowfall-lib (packages, modules, overlays, systems,
          homes, shells, checks, templates, libraries) or configuring `mkFlake`
          (namespace, channels-config, alias, external modules). Also covers
          v1→v2/v3 migrations and "where does this file go" debugging.
          Triggers: "snowfall", "mkFlake", "add module", "add package",
          "add system", "add home", "add overlay", "add shell", "add check",
          "add template", "add library"
          Preconditions: flake.nix uses snowfall-lib input.
          Constraints: preserve existing `snowfall.namespace`; files must be
          `default.nix`; new files must be `git add`-ed before `nix flake show`
          will see them.
        '';
      };
    };
  };
in
{
  # Re-export merged skills at the system level so other modules
  # (notably local.hermes.extraSkillsDir) can read the same derivation.
  options.local.agentic-stack.mergedSkills = lib.mkOption {
    type = lib.types.path;
    default = mergedSkills;
    readOnly = true;
    description = ''
      Path to the merged agentic-stack skills derivation. Built by
      `inputs.schrodinger-agentic-stack.lib.<system>.mergeSkills`. Includes
      the fork's bundled seed skills plus project-specific extras
      (currently: snowfall-lib).
    '';
  };

  config.home-manager.users.${user.name} =
    { ... }:
    {
      imports = [ inputs.schrodinger-agentic-stack.homeManagerModules.default ];

      programs.agentic-stack = {
        enable = true;

        # Layered skills: bundled + snowfall-lib.
        skills.merged = mergedSkills;

        # Bundle mode: serialize provider config to .agent/providers.json.
        providers.bundle = {
          enable = true;
          config = {
            litellm = lib.salt.ai.providers.litellm // {
              apiKeyFile = config.local.ai.providers.litellm.apiKeyFile or null;
            };
            vertex = lib.salt.ai.providers.vertex;
            azure = lib.salt.ai.providers.azure // {
              apiKeyFile = config.local.ai.providers.azure.apiKeyFile or null;
            };
            omlx = lib.salt.ai.providers.omlx;
          };
        };

        providers.tools.enable = false;

        # Claude Code adapter: own .claude/settings.json + .claude/skills.
        # bd-prime hooks (SessionStart, PreCompact) merge with agentic-stack's
        # PostToolUse + Stop defaults via lib.recursiveUpdate in the fork module.
        harnesses.claude-code = {
          enable = true;
          extraHooks = {
            SessionStart = [
              {
                matcher = "";
                hooks = [
                  {
                    type = "command";
                    command = "bd prime";
                  }
                ];
              }
            ];
            PreCompact = [
              {
                matcher = "";
                hooks = [
                  {
                    type = "command";
                    command = "bd prime";
                  }
                ];
              }
            ];
          };
        };

        # Nightly dream cycle.
        autoDream = {
          enable = true;
          projectRoot = "/Users/${user.name}/.config/nixos-config";
          schedule = {
            Hour = 3;
            Minute = 0;
          };
        };
      };
    };
}
