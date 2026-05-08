{
  lib,
  pkgs,
  ...
}:

let
  hostname = "L75T4YHXV7-MBA";
in
{
  networking.hostName = hostname;

  # ── Lean-compute-node overrides ─────────────────────────────────────
  # This Mac is a 16 GB Apple Silicon laptop used as a compute-attached
  # cluster node. Keep everything the shared darwin config sets so fleet
  # metrics stay complete (see local.darwinObservability — kept on every node).
}
