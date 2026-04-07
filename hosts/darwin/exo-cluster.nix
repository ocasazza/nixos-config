# Exo distributed inference cluster configuration.
# Imported by per-machine darwin configs that participate in the cluster.
# Each machine receives exoPeers, exoPackage, and exoNetwork via specialArgs.
# exoListenInterfaces is kept for backwards compat but unused when network != "auto".
{
  exoPeers,
  exoPackage,
  exoNetwork ? "thunderbolt",
  exoListenInterfaces ? [ ],
  ...
}:
{
  local.hermes.exo = {
    enable = true;
    package = exoPackage;
    peers = exoPeers;
    listenInterfaces = exoListenInterfaces;
    network = exoNetwork;
  };
}
