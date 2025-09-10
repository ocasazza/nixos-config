{
  config,
  pkgs,
  home-manager,
  user,
  nvf,
  ...
}:

let
  sharedFiles = import ../shared/files.nix { inherit config pkgs user; };
  additionalFiles = import ./files.nix { inherit config pkgs user; };
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

  homebrew = {
    enable = true;
    brewPrefix = "/opt/homebrew/bin";
    global = {
      brewfile = true;
      autoUpdate = false;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    taps = [];
    casks = [
      # Development Tools
      "zoc"
      # Communication Tools
      "meetingbar"
      "notion"
      # Browsers
      "google-chrome"
      # mac stuff
      "hiddenbar"
    ];
    brews = [];
    # $ nix shell nixpkgs#mas
    # $ mas search <app name>
    masApps = {
      "Fresco" = 1251572132;
    };
  };

    home-manager = {
      useGlobalPkgs = true;
      users.${user.name} =
        {
          pkgs,
          config,
          lib,
          ...
        }:
        {
        imports = [ nvf.homeManagerModules.default ];
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
            inherit config pkgs lib user;
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
