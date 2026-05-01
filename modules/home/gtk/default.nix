{ config, ... }:

# Snowfall auto-discovers this as a homeModule and applies it to all
# home-manager users via `home-manager.sharedModules`. We only set the
# theme/icon NAMES; home-manager's own NixOS shim (`nixos/common.nix`)
# already provides the `package` attribute pointing at adwaita-icon-theme,
# so duplicating it here triggers an "option defined multiple times" error
# even when the values are identical.
{
  gtk = {
    enable = true;
    theme.name = "Adwaita-dark";
    iconTheme.name = "Adwaita-dark";
    # Pin gtk4.theme to gtk.theme — preserves home-manager pre-26.05
    # default; silences the deprecation warning without changing behavior.
    gtk4.theme = config.gtk.theme;
  };
}
