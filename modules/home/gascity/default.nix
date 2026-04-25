{ ... }:
# Always-on enable for gascity (`gc`) on every fleet HM user.
#
# The actual options + package wiring live in the upstream
# gascity-flake (`inputs.gascity-flake.homeManagerModules.default`,
# imported by `homes/aarch64-darwin/casazza@*/default.nix`). This
# snowfall-auto-discovered module just flips it on so `gc` (and `bd`,
# via `enableBeads = true` by default) land on PATH everywhere — same
# behavior as the previous inline `home.packages` list.
#
# Per-host overrides (different provider/model defaults, extraPackages,
# disabling a runtime dep) belong in
# `homes/aarch64-darwin/casazza@<host>/default.nix`.
{
  programs.gascity.enable = true;
}
