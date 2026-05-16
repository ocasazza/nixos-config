# Shared agent skills and commands from nason-skills and olive-skills.
# Exposes `config.local.skills` and `config.local.commands` for consumer modules
# (hermes extraSkillsDir, pi skills symlink, claude .claude/skills+commands, etc.).
{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  sys = pkgs.stdenv.hostPlatform.system;
  nasonPkgs = inputs.nason-skills.packages.${sys};
  olivePkgs = inputs.olive-skills.packages.${sys};
  mergedSkills = pkgs.symlinkJoin {
    name = "merged-skills";
    paths = [
      nasonPkgs.default
      olivePkgs.default
    ];
  };
in
{
  options.local.skills = {
    nason = {
      package = lib.mkOption {
        type = lib.types.package;
        default = nasonPkgs.default;
        readOnly = true;
        description = "Derivation containing all nason-skills.";
      };
      path = lib.mkOption {
        type = lib.types.path;
        default = nasonPkgs.default;
        readOnly = true;
        description = "Path to nason-skills (alias for package).";
      };
    };
    olive = {
      package = lib.mkOption {
        type = lib.types.package;
        default = olivePkgs.default;
        readOnly = true;
        description = "Derivation containing all olive-skills.";
      };
      path = lib.mkOption {
        type = lib.types.path;
        default = olivePkgs.default;
        readOnly = true;
        description = "Path to olive-skills (alias for package).";
      };
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = mergedSkills;
      readOnly = true;
      description = "Merged derivation containing skills from both repos.";
    };
    path = lib.mkOption {
      type = lib.types.path;
      default = mergedSkills;
      readOnly = true;
      description = "Path to merged skills (alias for package).";
    };
  };

  options.local.commands = {
    package = lib.mkOption {
      type = lib.types.package;
      default = olivePkgs.commands;
      readOnly = true;
      description = "Derivation containing all olive-skills commands.";
    };
    path = lib.mkOption {
      type = lib.types.path;
      default = olivePkgs.commands;
      readOnly = true;
      description = "Path to olive-skills commands (alias for package).";
    };
  };
}
