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

  # ── Lean-node overrides ────────────────────────────────────────────
  # CK2 is a compute-attached cluster node. The shared darwin defaults
  # in hosts/darwin/default.nix already gate oMLX, exo, hippo.obsidianSync,
  # and hermes.voice on `isWorkstation` (GN9-only). The remaining
  # overrides below kill the still-on workstation services that don't
  # belong on a lean compute node:
  #   * obsidianVault — the vault repo isn't authored from this Mac, so
  #     reingestAuto's hourly `opencode run /reingest -` (~900 MiB RSS)
  #     and the vault-snapshot-watch fswatch agent are pure overhead.
  local.obsidianVault.enable = lib.mkForce false;
}
