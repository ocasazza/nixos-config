# Exo distributed inference cluster configuration.
# Imported by per-machine darwin configs that participate in the cluster.
# Each machine receives `exoPeers` and `exoListenInterfaces` via specialArgs.
{
  exoPeers,
  exoListenInterfaces ? [ "en0" ],
  ...
}:
{
  local.hermes.exo = {
    enable = true;
    peers = exoPeers;
    listenInterfaces = exoListenInterfaces;
  };
}
