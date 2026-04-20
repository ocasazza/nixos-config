{
  config,
  pkgs,
  lib,
  user,
  inputs,
  ...
}:

let
  #xdg_configHome = "/home/${user}/.config";
  shared-programs = import ../shared/home-manager.nix {
    inherit
      config
      pkgs
      lib
      user
      inputs
      ;
  };
  shared-files = import ../shared/files.nix { inherit config pkgs user; };
in
{
  # Snowfall auto-discovers everything in modules/home/ and applies it
  # to home-manager users via home-manager.sharedModules in flake.nix.
  # We only need to import flake-input-provided HM modules here.
  imports = [
    inputs.nix4nvchad.homeManagerModule
  ];

  home = {
    enableNixpkgsReleaseCheck = false;
    username = "${user.name}";
    homeDirectory = "/home/${user.name}";
    packages = pkgs.callPackage ./packages.nix { };
    file = shared-files // import ./files.nix { inherit user; };
    stateVersion = "21.05";

    keyboard = {
      layout = "us";
      variant = "dvorak";
    };
  };

  programs = lib.mkMerge [
    shared-programs
    (import ./programs/foot.nix {
      inherit
        config
        pkgs
        lib
        user
        inputs
        ;
    })
  ];
}
