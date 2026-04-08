# Exo distributed inference cluster configuration.
# Imported by per-machine darwin configs that participate in the cluster.
# Each machine receives exoPeers, exoPackage, exoNetwork, TB cluster
# membership, and thunderboltLinks via specialArgs from the flake.
{
  exoPeers,
  exoPackage,
  exoNetwork ? "thunderbolt",
  exoListenInterfaces ? [ ],
  exoThunderboltHostname ? null,
  exoThunderboltCluster ? [ ],
  thunderboltLinks ? [ ],
  ...
}:
{
  local.hermes.exo = {
    enable = true;
    package = exoPackage;
    peers = exoPeers;
    listenInterfaces = exoListenInterfaces;
    network = exoNetwork;
    thunderboltHostname = exoThunderboltHostname;
    thunderboltCluster = exoThunderboltCluster;
    inherit thunderboltLinks;
  };
}
