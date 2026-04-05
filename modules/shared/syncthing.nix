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
#   3. Open http://localhost:8384 in a browser
#   4. Add your other devices by device ID
#   5. Share folders between devices
#
# The default sync folder is ~/Sync. Add more folders via the web UI
# or by extending this config.
{ ... }:
{
  services.syncthing = {
    enable = true;

    # Syncthing settings are written to config.xml on first run.
    # After that, changes made in the web UI take precedence.
    # Set overrideFolders/overrideDevices to true to enforce declarative config.
    overrideFolders = false;
    overrideDevices = false;

    settings = {
      options = {
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1; # Decline usage reporting
      };

      folders = {
        "default" = {
          path = "~/Sync";
          label = "Sync";
          fsWatcherEnabled = true;
        };
      };
    };
  };
}
