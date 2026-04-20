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

  # Claude Code with Vertex AI proxy
  programs.claude-code = {
    enable = true;
    model = "claude-opus-4-7";
    vertex = {
      enable = true;
      projectId = "vertex-code-454718";
      region = "us-east5";
      baseURL = "https://vertex-proxy.sdgr.app/v1";
    };
    apiKeyHelper = true;
  };
}
