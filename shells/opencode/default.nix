{
  pkgs,
  ...
}:

# Opt-in opencode variant — `nix develop .#opencode`.
# Routes gc commands to the `schrodan-oc` rig (oc pack, opencode →
# LiteLLM proxy on desk-nxst-001:4000 with role-based aliases).
# Register the rig once before first use:
#   gc rig add ~/Repositories/na-son/schrodan \
#     --name schrodan-oc \
#     --include packs/schrodinger/oc \
#     --start-suspended
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    bashInteractive
    git
    statix
    deadnix
    nh
  ];
  shellHook = ''
    export EDITOR=nvim
    export GC_RIG_DEFAULT=schrodan-oc
    gc() { command gc --rig "$GC_RIG_DEFAULT" "$@"; }
    bd() { command gc --rig "$GC_RIG_DEFAULT" bd "$@"; }
    export -f gc bd 2>/dev/null || true
  '';
}
