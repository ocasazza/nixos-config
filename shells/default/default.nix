{
  pkgs,
  ...
}:

# Default devshell — claude-code variant of the schrodan four-agent setup.
#   gc commands route to the `schrodan` rig (cc pack, claude-code direct).
# Opt into the opencode variant with `nix develop .#opencode`.
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
    export GC_RIG_DEFAULT=schrodan
    gc() { command gc --rig "$GC_RIG_DEFAULT" "$@"; }
    bd() { command gc --rig "$GC_RIG_DEFAULT" bd "$@"; }
    export -f gc bd 2>/dev/null || true
  '';
}
