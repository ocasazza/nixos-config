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
  imports = [
    inputs.nix4nvchad.homeManagerModule
    ./gtk
    ./sway
    ./services
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
