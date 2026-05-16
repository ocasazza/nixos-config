{ pkgs, ... }:

{
  home.packages = [
    pkgs.opencode
    pkgs.opencode-voice
    pkgs.bun
  ];

  home.sessionVariables = { };
  home.sessionVariablesExtra = "";
}
