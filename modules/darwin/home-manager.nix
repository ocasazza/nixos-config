{
  config,
  pkgs,
  user,
  ...
}:

let
  sharedFiles = import ../shared/files { inherit config pkgs user; };
  additionalFiles = import ./files { inherit config pkgs user; };
in
{
  imports = [
    ./dock
  ];

  users.users.${user.name} = {
    name = "${user.name}";
    home = "/Users/${user.name}";
    isHidden = false;
    shell = pkgs.zsh;
  };

  # Homebrew managed by Fleet MDM instead of nix-darwin
  homebrew = {
    enable = false; # Disabled: managed by Fleet MDM
    # prefix = "/opt/homebrew";
    # global = {
    #   brewfile = true;
    #   autoUpdate = false;
    # };
    # onActivation = {
    #   autoUpdate = false;
    #   upgrade = false;
    #   cleanup = "zap";
    # };
    # taps = [
    #   "vjeantet/tap"
    # ];
    # casks = [
    #   "ghostty"
    #   "meetingbar"
    #   "hiddenbar"
    # ];
    # brews = [
    #   "vjeantet/tap/alerter"
    # ];
    # # $ nix shell nixpkgs#mas
    # # $ mas search <app name>
    # masApps = {
    #   "Fresco" = 1251572132;
    # };
  };

  home-manager = {
    useGlobalPkgs = true;
    users.${user.name} =
      {
        pkgs,
        config,
        lib,
        inputs,
        ...
      }:
      {
        imports = [
          inputs.nix4nvchad.homeManagerModule
        ];
        home = {
          packages = pkgs.callPackage ./packages.nix { };
          file = lib.mkMerge [
            sharedFiles
            additionalFiles
          ];
          stateVersion = "23.11";
        };
        programs = lib.mkMerge [
          (import ../shared/home-manager.nix {
            inherit
              config
              pkgs
              lib
              user
              ;
          })
          {
            # Override ghostty to use the binary package from Nix
            ghostty.package = lib.mkForce pkgs.ghostty-bin;
          }
        ];
        manual.manpages.enable = false;
      };
  };

  local.dock = {
    enable = true;
    entries = [
      { path = "/Applications/Google Chrome.app/"; }
      { path = "/Applications/Ghostty.app/"; }
      { path = "/Applications/Visual Studio Code.app/"; }
      { path = "/Applications/Notion.app/"; }
      {
        path = "/Users/${user.name}/Downloads";
        options = "--display stack --view list";
        section = "others";
      }
      {
        path = "/Users/${user.name}/src";
        options = "--view list";
        section = "others";
      }
    ];
  };
}
