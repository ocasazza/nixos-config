{ ... }:

# fzf integration: Ctrl-R (history), Ctrl-T (files), Alt-C (cd).
# Snowfall auto-discovers this module and applies it to every HM user.
{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--info=inline"
    ];
    # use fd for faster file/directory traversal if available
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :100 {}'" ];
    changeDirWidgetOptions = [ "--preview 'ls -1 --color=always {}'" ];
  };
}
