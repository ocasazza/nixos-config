{
  config,
  lib,
  user,
  ...
}:

with lib;

{
  options.local.agentInstructions = {
    enable = mkEnableOption "Agent instructions (AGENTS.md, CLAUDE.md, GEMINI.md)";

    nixosConfigPath = mkOption {
      type = types.path;
      default = "${config._module.args.self}/..";
      description = "Path to nixos-config directory";
    };
  };

  config = mkIf config.local.agentInstructions.enable {
    home-manager.users.${user.name} = {
      home.file."AGENTS.md" = {
        source = "${config.local.agentInstructions.nixosConfigPath}/AGENTS.md";
        executable = false;
      };

      home.file."CLAUDE.md" = {
        source = "${config.local.agentInstructions.nixosConfigPath}/AGENTS.md";
        executable = false;
      };

      home.file."GEMINI.md" = {
        source = "${config.local.agentInstructions.nixosConfigPath}/AGENTS.md";
        executable = false;
      };
    };
  };
}
