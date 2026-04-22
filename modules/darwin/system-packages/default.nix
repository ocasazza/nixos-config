{ pkgs, ... }:

# Darwin-specific system packages. Snowfall auto-discovers this module
# and applies it to every darwin host. Shared cross-arch packages live
# in `modules/shared/system-packages`, explicitly imported here so
# both are installed in a single module evaluation (snowfall's shared
# namespace isn't auto-applied).
{
  imports = [
    ../../shared/system-packages
  ];

  environment.systemPackages = with pkgs; [
    dockutil
    gnugrep
    ghostty-bin
    yubikey-manager

    # Personal knowledge management
    obsidian
  ];
}
