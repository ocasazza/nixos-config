{
  lib,
  pkgs,
  ...
}:

let
  hostname = "GN9CFLM92K-MBP";
  exoPeers = lib.salt.exoPeersFor hostname;
in
{
  imports = [
    ../../../hosts/darwin
    ../../../hosts/darwin/exo-cluster.nix
  ];

  networking.hostName = hostname;

  # The other cluster nodes (CK2Q9LN7PM-MBA, GJHC5VVN49-MBP, L75T4YHXV7-MBA)
  # aren't reachable from this machine right now (mDNS doesn't resolve them),
  # so leaving distributed builds on adds 5s + ConnectTimeout per builder
  # to every `nix develop` / `direnv allow`. Re-enable when the cluster
  # is back on the same network.
  casazza.distributedBuilds.enable = false;

  # Hold the JuiceFS mount launchd daemon offline until macFUSE's kext
  # is approved in System Settings → Privacy & Security ("allow loading
  # system software from developer Benjamin Fleischer", developer ID
  # 3T5GSNBU6W). Without that approval, mount_macfuse pops a
  # notification every few seconds and the launchd job thrashes.
  #
  # The mount config (services.juicefs.mounts.shared) stays defined so
  # /var/lib/juicefs-secrets + the sops-managed redis password get
  # provisioned by the rebuild as usual; only the launchd respawn loop
  # is suppressed. Once the kext is approved (one-time, user-interactive),
  # remove this override and re-run `darwin-rebuild switch` — or just
  # `sudo launchctl load /Library/LaunchDaemons/org.juicefs.mount-shared.plist`.
  #
  # The upstream darwin juicefs module hardcodes KeepAlive=true /
  # RunAtLoad=true; this `Disabled = true` override is the lowest-blast-
  # radius way to neutralize them without forking the module.
  launchd.daemons.juicefs-mount-shared.serviceConfig = {
    RunAtLoad = lib.mkForce false;
    KeepAlive = lib.mkForce false;
    Disabled = lib.mkForce true;
  };

  # Pass exo cluster args that exo-cluster.nix expects
  _module.args = {
    exoPeers = exoPeers;
    exoPackage = pkgs.exo;
    exoNetwork = "thunderbolt";
    exoListenInterfaces = [ ];
    exoThunderboltHostname = hostname;
    exoThunderboltCluster = lib.salt.thunderboltHosts;
    thunderboltLinks = lib.salt.thunderboltLinks;
  };
}
