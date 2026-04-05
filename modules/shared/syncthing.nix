# ── Syncthing ────────────────────────────────────────────────────────────
# Continuous file synchronization across all machines running nixos-config.
#
# Each machine is uniquely identified by its hostname. Syncthing generates
# a certificate/key pair on first run (stored in the syncthing data dir).
# The device ID is derived from this certificate.
#
# Pairing:
#   On each machine, after activation, run:
#     syncthing cli show system | grep myID
#   Then add the device ID on the other machine via the web UI at
#   http://localhost:8384 or via:
#     syncthing cli config devices add --device-id <ID> --name <hostname>
#
# Default sync folder: ~/Repositories
{ ... }:
{
  services.syncthing = {
    enable = true;

    # Declarative config is authoritative — removes folders/devices
    # not defined here. Use the web UI to add folders/devices, then
    # mirror them here to persist across rebuilds.
    overrideFolders = true;
    overrideDevices = true;

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
}
