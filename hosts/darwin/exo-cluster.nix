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

    # Reverse-tunnel the local exo API to desk-nxst-001 so its LiteLLM
    # proxy can route a model group through 127.0.0.1:apiPort. Self-gated
    # to the relay node (the only one with myLinks > 1) — CK2/L75 take
    # the option but emit no daemon.
    litellmTunnel.enable = true;
  };
}
