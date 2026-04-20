{ ... }:

{
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
}
