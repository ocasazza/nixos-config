{
  pkgs,
  user,
  lib,
  config,
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
    # mas (Mac App Store) apps intentionally empty — the only previous
    # entry, `"Fresco" = 1251572132`, fails `brew bundle` fleet-wide
    # with "No apps found in the App Store for ADAM ID 1251572132"
    # (likely account/region-bound), which breaks activation now that
    # homebrew.enable=true. Add specific apps only after confirming the
    # Apple ID that each Mac runs under can actually see them.
    # $ nix shell nixpkgs#mas
    # $ mas search <app name>
    masApps = { };
  };

  # Make `brew bundle` non-fatal during activation. nix-darwin runs the
  # bundle under `set -euo pipefail`, so a single failed cask (e.g.
  # ghostty's stale .incomplete lock, meetingbar's overwrite conflict,
  # alerter requiring a newer Xcode CommandLineTools) aborts the whole
  # postActivation phase — including the Thunderbolt mesh setup further
  # down. Per-host brew failures should warn but not block.
  system.activationScripts.homebrew.text = lib.mkForce ''
    echo >&2 "Homebrew bundle..."
    if [ -f "${config.homebrew.prefix}/bin/brew" ]; then
      PATH="${config.homebrew.prefix}/bin:${lib.makeBinPath [ pkgs.mas ]}:$PATH" \
      sudo \
        --preserve-env=PATH \
        --user=${lib.escapeShellArg config.homebrew.user} \
        --set-home \
        env \
        ${config.homebrew.onActivation.brewBundleCmd} || \
        echo >&2 "warning: brew bundle exited non-zero; continuing activation"
    else
      echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
    fi
  '';

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
