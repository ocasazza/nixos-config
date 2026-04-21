{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.local.notifications;
in
{
  options.local.notifications = {
    enable = mkOption {
      type = types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = ''
        Enable desktop notification daemon (mako on Wayland).

        Auto-enables on Linux and auto-disables on Darwin so this
        home-manager module — auto-discovered via snowfall and applied
        through `home-manager.sharedModules` — never tries to start a
        Wayland notifier on macOS.
      '';
    };
  };

  config = mkIf cfg.enable {
    services = {
      # notifications
      mako = {
        enable = true;
        settings = {
          default-timeout = 10000;
        };
      };

      # Automount
      # udiskie.enable = true;
    };
  };
}
