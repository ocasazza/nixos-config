{
  pkgs,
  user,
  ...
}:

# nix-darwin system-level config that lives close to the user account.
# The actual home-manager config has been moved to the snowfall home at
# `homes/aarch64-darwin/casazza/default.nix`; snowfall auto-wires it
# into every Darwin system, so we no longer set `home-manager.users.*`
# from this file.
#
# What stays here (Darwin-system-level, not home-manager):
#   * users.users.<name>         — the macOS account record
#   * homebrew                   — taps/casks/brews/masApps
#   * local.dock                 — dock entries (custom module)
{
  users.users.${user.name} = {
    name = "${user.name}";
    home = "/Users/${user.name}";
    isHidden = false;
    shell = pkgs.zsh;
  };

  # Homebrew is partly Fleet MDM-managed; nix-darwin layers on top to
  # install specific casks we depend on (currently just macFUSE for the
  # shared JuiceFS mount). `cleanup = "none"` is deliberate — we do NOT
  # want nix-darwin to remove casks/brews that Fleet or the user
  # installed imperatively. Flip to "uninstall"/"zap" only after the
  # full declared list is audited against every Mac's imperative state.
  homebrew = {
    enable = true;
    prefix = "/opt/homebrew";
    global = {
      brewfile = true;
      autoUpdate = false;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
    taps = [
      "vjeantet/tap"
    ];
    casks = [
      "ghostty"
      "hiddenbar"
      # macFUSE kernel extension — required by services.juicefs on
      # darwin. Installing this cask still requires a one-time kext
      # approval in System Settings → Privacy & Security and a reboot
      # before the FUSE mount utility becomes usable (`juicefs` otherwise
      # errors with `fuse: no FUSE mount utility found`).
      "macfuse"
      "meetingbar"
    ];
    brews = [
      "vjeantet/tap/alerter"
    ];
    # $ nix shell nixpkgs#mas
    # $ mas search <app name>
    masApps = {
      "Fresco" = 1251572132;
    };
  };

  local.dock = {
    enable = true;
    entries = [
      { path = "/Applications/Google Chrome.app/"; }
      { path = "/Applications/Ghostty.app/"; }
      { path = "/Applications/Visual Studio Code.app/"; }
      { path = "/Applications/Notion.app/"; }
      {
        path = "/Users/${user.name}/Downloads";
        options = "--display stack --view list";
        section = "others";
      }
      {
        path = "/Users/${user.name}/src";
        options = "--view list";
        section = "others";
      }
    ];
  };
}
