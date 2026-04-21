{
  config,
  ...
}:

# Ghostty terminal. Snowfall auto-discovers this module and applies it
# to every HM user. The `command` path points at the per-user zsh
# profile (nix-darwin / nixos-level install).
{
  programs.ghostty = {
    enable = true;
    # package = null;
    settings = {
      font-size = 14;
      font-family = "JetBrainsMono Nerd Font Mono";
      theme = "Monokai Soda";
      cursor-style = "block";
      shell-integration-features = "no-cursor";
      clipboard-paste-protection = false;
      copy-on-select = true;
      term = "xterm-256color";
      macos-titlebar-proxy-icon = "hidden";
      # Window border
      window-padding-color = "extend";
      window-padding-x = 4;
      window-padding-y = 4;
      unfocused-split-fill = "#b4a7d6";
      # Shader effects
      background-opacity = 0.95;
      background-blur-radius = 20;
      config-file = "~/.config/ghostty/extra"; # for testing custom shaders
      command = "/etc/profiles/per-user/${config.home.username}/bin/zsh";
      # Pane/split management is owned by Zellij — explicitly unbind
      # Ghostty's defaults so cmd+shift+{d,e,o} pass through to the
      # shell (and so muscle memory doesn't accidentally create a
      # Ghostty split inside an existing Zellij session).
      keybind = [
        "cmd+shift+d=unbind"
        "cmd+shift+e=unbind"
        "cmd+shift+o=unbind"
        "cmd+d=unbind"
      ];
    };
  };
}
