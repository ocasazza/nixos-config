{ pkgs, ... }:

# Open agent skills CLI.
# Snowfall auto-discovers this shared module and applies it to every HM user.
{
  home.packages = [
    pkgs.skills
  ];
}
