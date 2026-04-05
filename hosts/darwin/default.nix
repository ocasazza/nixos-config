{
  pkgs,
  user,
  config,
  ...
}:

let
  wallpaper = ../../modules/darwin/files/AFRC2017-0233-007-large.jpg;
in
{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
    ../../modules/shared/cachix
  ];

  # Enable autopkgserver for Fleet GitOps package building
  services.autopkgserver = {
    enable = true;
    # Point to git-fleet repo for recipe overrides (development machine only)
    recipeOverrideDirs = "/Users/${user.name}/Repositories/schrodinger/git-fleet/lib/software";
  };

  # Set desktop wallpaper
  system.activationScripts.postActivation.text = ''
    sudo -u ${user.name} osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"'
  '';

  # Load Fleet secrets into user's shell environment
  # Creates a .fleet_secrets file in the user's home directory
  system.activationScripts.fleetSecrets.text = ''
    echo "Loading Fleet MDM secrets..."
    FLEET_SECRETS_FILE="${config.sops.secrets.fleet.path}"
    USER_ENV_FILE="/Users/${user.name}/.fleet_secrets"

    if [ -f "$FLEET_SECRETS_FILE" ]; then
      cp "$FLEET_SECRETS_FILE" "$USER_ENV_FILE"
      chown ${user.name}:staff "$USER_ENV_FILE"
      chmod 600 "$USER_ENV_FILE"
      echo "Fleet secrets loaded to $USER_ENV_FILE"
    else
      echo "Warning: Fleet secrets file not found at $FLEET_SECRETS_FILE"
    fi
  '';

  # Determinate Nix manages the daemon, nix binary, and nix.conf.
  # Don't let nix-darwin override it with a nixpkgs nix package.
  # See: https://docs.determinate.systems/getting-started/individual-install/#with-nix-darwin
  nix.enable = false;

  environment.systemPackages = with pkgs; import ../../modules/shared/packages.nix { inherit pkgs; };

  # Set system-wide environment variables
  environment.variables = {
    # NH Darwin flake configuration
    NH_DARWIN_FLAKE = ".#darwinConfigurations.macos";
    # SOPS key file location
    SOPS_AGE_KEY_FILE = "/Users/${user.name}/.config/sops/age/keys.txt";
    # Nix configuration
    NIXPKGS_ALLOW_UNFREE = "1";
    # Git SSH configuration
    GIT_SSH_COMMAND = "ssh -i /Users/${user.name}/.ssh/id_ed25519 -o IdentitiesOnly=yes";
  };

  # Auto-load direnv for Claude Code (avoids needing nix develop)
  # Uses programs.zsh.shellInit for all zsh shells (interactive and non-interactive)
  programs.zsh.shellInit = ''
    # Load Fleet MDM secrets
    if [ -f "$HOME/.fleet_secrets" ]; then
      set -a
      source "$HOME/.fleet_secrets"
      set +a
    fi

    if command -v direnv >/dev/null 2>&1; then
      if [ -n "$CLAUDECODE" ]; then
        eval "$(direnv hook zsh)"
        # Trigger direnv to load .envrc in current directory
        if [ -f ".envrc" ]; then
          _direnv_hook
        fi
      fi
    fi
  '';

  security.pam.services.sudo_local.enable = false;

  # BeyondTrust blocks /etc/pam.d writes
  # security.pam.services.sudo_local = {
  #   enable = true;
  #   reattach = true;
  #   touchIdAuth = true;
  #   watchIdAuth = true;
  # };

  system = {
    stateVersion = 5;
    primaryUser = user.name;
    #checks.verifyNixPath = false;
    # https://mynixos.com/nix-darwin/options/system.defaults
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;
        AppleICUForce24HourTime = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;

        KeyRepeat = 2; # 120, 90, 60, 30, 12, 6, 2
        InitialKeyRepeat = 15; # 120, 94, 68, 35, 25, 15

        # unavailable preferences can be accessed using quotes
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };

      CustomUserPreferences = {
        "com.apple.Spotlight" = {
          "com.apple.Spotlight MenuItemHidden" = 1;
        };
        NSGlobalDomain = {
          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
        };
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.screencapture" = {
          location = "~/Screenshots";
          type = "png";
        };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;
      };

      dock = {
        # the rest of the dock settings are in modules/darwin/home-manager.nix
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.001;
        mru-spaces = false;
        show-recents = false;
        tilesize = 48;
        appswitcher-all-displays = true;
        dashboard-in-overlay = false;
        enable-spring-load-actions-on-all-items = false;
        expose-animation-duration = 0.2;
        expose-group-apps = false;
        launchanim = true;
        mineffect = "genie";
        minimize-to-application = false;
        mouse-over-hilite-stack = true;
        orientation = "bottom";
        show-process-indicators = true;
        showhidden = false;
        static-only = true;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };

      finder = {
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirst = true;
        # When performing a search, search the current folder by default
        AppleShowAllExtensions = true;
        FXDefaultSearchScope = "SCcf";
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowPathbar = true;
        ShowRemovableMediaOnDesktop = true;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };
  };
}
