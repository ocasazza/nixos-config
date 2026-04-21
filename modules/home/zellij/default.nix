{ ... }:

# Zellij terminal multiplexer. Snowfall auto-discovers this module and
# applies it to every HM user.
{
  programs.zellij = {
    enable = true;
    # HM's zsh integration injects an auto-start snippet that honors
    # $ZELLIJ_AUTO_ATTACH / $ZELLIJ_AUTO_EXIT (set in zsh.sessionVariables
    # above), so every new Ghostty pane attaches to (or creates) a
    # session and exits cleanly on detach.
    enableZshIntegration = true;
    settings = {
      # Don't show the startup tip / first-run wizard.
      show_startup_tips = false;
      show_release_notes = false;
      # Pane frames eat horizontal space; rely on Ghostty's split-fill
      # color and Zellij's status bar to indicate focus instead.
      pane_frames = false;
      # Use the same family as Ghostty so the embedded UI feels native.
      default_layout = "compact";
      # Match Ghostty's Monokai-ish vibe.
      theme = "monokai-soda";
      themes.monokai-soda = {
        fg = [
          248
          248
          242
        ];
        bg = [
          26
          26
          26
        ];
        black = [
          26
          26
          26
        ];
        red = [
          249
          38
          114
        ];
        green = [
          166
          226
          46
        ];
        yellow = [
          244
          191
          117
        ];
        blue = [
          102
          217
          239
        ];
        magenta = [
          174
          129
          255
        ];
        cyan = [
          161
          239
          228
        ];
        white = [
          248
          248
          242
        ];
        orange = [
          253
          151
          31
        ];
      };
      # Ctrl-based prefixes don't collide with AeroSpace (alt-only) or
      # Ghostty (now stripped of cmd+shift splits).
      copy_on_select = true;
      mouse_mode = true;
    };
  };
}
