# twg: Home Manager configuration (binary, skills install, user-level config).
#
# Shared, platform-agnostic Home Manager config. Imported by
# modules/darwin/twg/default.nix for macOS-specific wiring (if needed).
{
  lib,
  pkgs,
  ...
}:

let
  user = lib.salt.user;
in
{
  home-manager.users.${user.name} =
    { lib, ... }:
    {
      # TWG binary installation at user level
      home.packages = [ pkgs.twg ];

      # Install TWG agent skills to ~/.claude/skills/ and ~/.agents/skills/.
      # The `twg skills install --global` command creates skill files in:
      #   - ~/.claude/skills/twg/SKILL.md (operating contracts, command discovery)
      #   - ~/.claude/skills/twg-workflows/SKILL.md (outcome-focused recipes)
      #   - ~/.agents/skills/ (cross-agent installation)
      #
      # These skills enable AI agents (Claude Code, Cursor, Copilot, etc.) to
      # interact with Jira, Confluence, and Bitbucket using natural language.
      home.activation.installTwgSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v twg >/dev/null 2>&1; then
          # Install skills globally for all detected agents
          $DRY_RUN_CMD twg skills install --global || {
            echo "Warning: Failed to install TWG skills. Run 'twg skills install --global' manually after setup." >&2
          }
        fi
      '';
    };
}
