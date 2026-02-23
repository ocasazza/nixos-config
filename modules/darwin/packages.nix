{ pkgs }:

with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
in
shared-packages
++ [
  dockutil
  libvirt
  gnugrep
  ghostty-bin
  python313Packages.docutils
  claude-code
]
