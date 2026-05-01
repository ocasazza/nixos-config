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
    # Provides `programs.gascity` and `programs.beads` HM options.
    # Snowfall auto-applies `modules/home/gascity/default.nix`, which
    # flips both on for the fleet.
    inputs.gascity-flake.homeManagerModules.default
  ];

  home = {
    stateVersion = "23.11";

    # Stock upstream opencode from nixpkgs. The user-level config at
    # ~/.config/opencode/opencode.json (rendered by
    # modules/darwin/opencode/default.nix) registers the custom providers
    # (litellm, exo, anthropic via vertex, azure, omlx) and MCP servers.
    packages = [
      pkgs.opencode
      # Voice control for opencode: local whisper.cpp STT, pushes text
      # into an opencode session over the HTTP API. Run `opencode-voice`
      # while opencode is serving on --port (default 4096).
      pkgs.opencode-voice
      # Needed to install opencode plugins (oh-my-opencode) from the
      # nix-managed package.json in ~/.config/opencode/.
      pkgs.bun
    ];

    file = lib.mkMerge [
      sharedFiles
      additionalFiles
    ];

    # Automatically install opencode plugins whenever the nix-managed
    # package.json changes. This keeps oh-my-opencode (and any future
    # plugins) in sync without manual bun install steps.
    activation.installOpencodePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v bun >/dev/null 2>&1 && [[ -f "$HOME/.config/opencode/package.json" ]]; then
        cd "$HOME/.config/opencode"
        # Only run install if node_modules is missing or package.json is newer.
        if [[ ! -d node_modules ]] || [[ package.json -nt node_modules/.package-lock ]]; then
          $DRY_RUN_CMD bun install --no-summary $VERBOSE_ARG
        fi
      fi
    '';
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
