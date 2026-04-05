# ── Syncthing ────────────────────────────────────────────────────────────
# Continuous file synchronization across all machines running nixos-config.
#
# Each machine is uniquely identified by its hostname. Syncthing generates
# a certificate/key pair on first run (stored in ~/.config/syncthing/).
# The device ID is derived from this certificate.
#
# Setup for a new machine:
#   1. Activate nix-darwin (nh darwin switch .#macos)
#   2. Syncthing starts automatically as a launchd/systemd user service
#   3. The Syncthing menubar icon appears (macOS) for status and quick access
#   4. Open http://localhost:8384 in a browser to pair devices
#   5. Add your other devices by device ID
#
# Default sync folder: ~/Repositories
{
  pkgs,
  lib,
  ...
}:
{
  services.syncthing = {
    enable = true;

    overrideFolders = false;
    overrideDevices = false;

    settings = {
      options = {
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
      };

      folders = {
        "repos" = {
          path = "~/Repositories";
          label = "Repositories";
          fsWatcherEnabled = true;
        };
      };
    };
  };

  # Native macOS menubar app for Syncthing status and quick access
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    pkgs.syncthing-macos
  ];
}
