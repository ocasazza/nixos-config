# Exo distributed inference cluster configuration.
# Imported by per-machine darwin configs that participate in the cluster.
# Each machine receives exoPeers, exoPackage, exoNetwork, TB cluster
# membership, and thunderboltLinks via specialArgs from the flake.
{
  lib,
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
    # mkDefault so hosts/darwin/default.nix can flip this off per-host
    # (e.g. via `isWorkstation` gate) without a definition conflict.
    enable = lib.mkDefault true;
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
