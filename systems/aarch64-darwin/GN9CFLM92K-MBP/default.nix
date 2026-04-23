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
