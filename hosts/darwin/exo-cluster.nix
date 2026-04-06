# Exo distributed inference cluster configuration.
# Imported by per-machine darwin configs that participate in the cluster.
# Each machine receives `exoPeers` and `exoListenInterfaces` via specialArgs.
{
  exoPeers,
  exoPackage,
  exoListenInterfaces ? [ "en0" ],
  ...
}:
{
  local.hermes.exo = {
    enable = true;
    package = exoPackage;
    peers = exoPeers;
    listenInterfaces = exoListenInterfaces;
  };
}
