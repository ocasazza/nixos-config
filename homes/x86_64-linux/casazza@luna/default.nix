# casazza on every x86_64-linux host (currently just luna).
#
# Snowfall lib auto-generates `homeConfigurations.casazza@<host>` AND
# wires this into every NixOS system on x86_64-linux as a system module
# (gated on host match). It also auto-discovers everything under
# `modules/home/` and adds them as `home-manager.sharedModules`, so we
# don't need to import them explicitly.
#
# How matching works (from snowfall-lib/home/default.nix):
#
#   host-matches = (specialArgs.host == host)
#                  || (specialArgs.host == "" && specialArgs.system == system);
#
# Because this directory is named `casazza` (no `@host`), the host
# string is empty and we match every system on this architecture. To
# pin a per-host override, create `homes/x86_64-linux/casazza@luna/`.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  user = lib.salt.user;
in
{
  imports = [
    # Flake-input HM modules (not auto-discovered by snowfall — those
    # are filesystem-discovered from `modules/home/`). nix4nvchad
    # provides the nvchad neovim distribution as a HM module.
    inputs.nix4nvchad.homeManagerModule
  ];

  home = {
    enableNixpkgsReleaseCheck = false;
    stateVersion = "21.05";

    keyboard = {
      layout = "us";
      variant = "dvorak";
    };

    # Per-user packages defined in modules/nixos/packages.nix. Kept there
    # for now to minimize churn; can be inlined if the file disappears.
    packages = pkgs.callPackage ../../../modules/nixos/packages.nix { };
  };

  # Cross-platform HM program config (zsh/git/ssh/zellij/nvim/etc.)
  # lives in individual modules under `modules/home/*` and is
  # auto-applied via snowfall's sharedModules pipeline; no explicit
  # import is needed here.
}
