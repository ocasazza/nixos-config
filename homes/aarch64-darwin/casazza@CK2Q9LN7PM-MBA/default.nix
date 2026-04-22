# casazza on every aarch64-darwin host (all 4 cluster Macs).
#
# See homes/x86_64-linux/casazza/default.nix for how snowfall's home
# matching works. This file applies to every Darwin system because it
# has no `@host` suffix in its directory name.
#
# For per-host overrides, create `homes/aarch64-darwin/casazza@<host>/`
# (e.g. one with extra brews or a different terminal pinned).
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  user = lib.salt.user;

  sharedFiles = import ../../../modules/shared/files { inherit config pkgs user; };
  additionalFiles = import ../../../modules/_darwin-support/files { inherit config pkgs user; };
in
{
  imports = [
    inputs.nix4nvchad.homeManagerModule
  ];

  home = {
    stateVersion = "23.11";

    # Schrodinger opencode fork is exposed as a flake input package.
    # System packages are handled by `modules/darwin/system-packages`
    # (snowfall auto-applies it to every darwin host). Here we only
    # add the opencode binary into the HM user profile when the flake
    # input is available.
    packages = lib.optional (inputs ? opencode) inputs.opencode.packages.${pkgs.system}.default;

    file = lib.mkMerge [
      sharedFiles
      additionalFiles
    ];
  };

  programs = {
    # Pin ghostty to the prebuilt binary on Darwin (the source build
    # via the ghostty flake input is slow and does not benefit from
    # the binary cache the same way). The rest of the ghostty config
    # lives in `modules/home/ghostty`, auto-applied via snowfall.
    ghostty.package = lib.mkForce pkgs.ghostty-bin;
  };

  manual.manpages.enable = false;
}
