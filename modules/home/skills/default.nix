{ pkgs, lib, ... }:

# Open agent skills CLI.
# Snowfall auto-discovers this shared module and applies it to every HM user.
{
  home.packages = with pkgs; [
    (import <nixpkgs> { system = pkgs.stdenv.hostPlatform.system; }).skills
  ];

  # Debug: verify the module is being loaded
  home.extraInit = ''
    echo "skills module loaded"
  '';
}
