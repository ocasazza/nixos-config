{
  lib,
  pkgs,
  ...
}:

let
  hostname = "GN9CFLM92K-MBP";
in
{
  networking.hostName = hostname;

  # The other cluster nodes (CK2Q9LN7PM-MBA, GJHC5VVN49-MBP, L75T4YHXV7-MBA)
  # aren't reachable from this machine right now (mDNS doesn't resolve them),
  # so leaving distributed builds on adds 5s + ConnectTimeout per builder
  # to every `nix develop` / `direnv allow`. Re-enable when the cluster
  # is back on the same network.
  casazza.distributedBuilds.enable = false;

}
