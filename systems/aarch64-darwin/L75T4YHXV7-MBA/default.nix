{
  lib,
  pkgs,
  ...
}:

let
  hostname = "L75T4YHXV7-MBA";
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

  # ── Lean-compute-node overrides ─────────────────────────────────────
  # This Mac is a 16 GB Apple Silicon laptop used as a compute-attached
  # cluster node. Drop the workstation-only Hermes 3D visualizer; keep
  # everything else the shared darwin config sets so fleet metrics
  # stay complete (see local.darwinObservability — kept on every node).
  local.hermes.claw3d.enable = lib.mkForce false;
}
