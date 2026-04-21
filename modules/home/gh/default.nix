{ ... }:

# GitHub CLI. Snowfall auto-discovers this module and applies it to
# every HM user.
{
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false; # https://github.com/NixOS/nixpkgs/issues/169115
  };
}
