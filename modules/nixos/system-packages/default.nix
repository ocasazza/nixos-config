{ pkgs, ... }:

# NixOS-specific system packages. Snowfall auto-discovers this module
# and applies it to every NixOS host. Shared cross-arch packages live
# in `modules/shared/system-packages`, explicitly imported here so
# both are installed in a single module evaluation (snowfall's shared
# namespace isn't auto-applied).
{
  imports = [
    ../../shared/system-packages
  ];

  environment.systemPackages = with pkgs; [

    # Security and authentication
    yubikey-agent

    # App and package management
    gnumake
    home-manager

    # Media and design tools
    fontconfig
    font-manager

    # Audio tools
    pavucontrol # Pulse audio controls

    # MISC DE / WM
    neovim
    mako
    foot
    wl-clipboard
    cliphist
    rofi
    rofi-calc

    # Testing and development tools
    nixpacks
    k9s

    # Core unix tools
    unixtools.ifconfig
    unixtools.netstat
    pciutils
    inotify-tools
    libnotify
    tuigreet

    sqlite
    xdg-utils
    xdg-user-dirs
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk

    # work
    containerlab
  ];
}
