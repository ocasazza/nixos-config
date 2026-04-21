{
  lib,
  pkgs,
  ...
}:

let
  hostname = "CK2Q9LN7PM-MBA";
  exoPeers = lib.salt.exoPeersFor hostname;
in
{
  imports = [
    ../../../hosts/darwin
    ../../../hosts/darwin/exo-cluster.nix
  ];

  networking.hostName = hostname;

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
