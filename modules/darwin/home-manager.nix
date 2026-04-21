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

  # Homebrew is managed by Fleet MDM rather than nix-darwin in this
  # environment, but we still declare the surface so `nix-homebrew`
  # knows what to expect if/when it's enabled.
  homebrew = {
    prefix = "/opt/homebrew";
    global = {
      brewfile = true;
      autoUpdate = false;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    taps = [
      "vjeantet/tap"
    ];
    casks = [
      "ghostty"
      "meetingbar"
      "hiddenbar"
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
