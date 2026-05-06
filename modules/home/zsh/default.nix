{
  pkgs,
  lib,
  osConfig ? null,
  ...
}:

# zsh: shell + completion + plugins (oh-my-zsh framework).
# Snowfall auto-discovers this module and applies it to every HM user.
# We derive hostName from osConfig.networking.hostName for darwin-specific
# features (nds function) and fall back to null so pure-HM contexts don't crash.
let
  hostName = if osConfig != null then osConfig.networking.hostName else null;
in
{
  programs.zsh = {
    enable = true;

    # ── Oh-My-Zsh configuration ───────────────────────────────
    ohMyZsh = {
      enable = true;
      template = "${pkgs.oh-my-zsh}/share/oh-my-zsh/templates/zshrc.oh-my-zsh.template";
      plugins = [
        "git"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "history-substring-search"
        "zsh-you-should-use"
      ];
    };

    # ── Init before compinit (OMZ calls compinit) ─────────────
    initExtraBeforeCompInit = ''
      # ── fzf-tab completion sources ──
      fpath=(\
        ${pkgs.zsh-fzf-tab}/share/fzf-tab \
        ${pkgs.zsh-completions}/share/zsh/site-functions \
        ${pkgs.nix-zsh-completions}/share/zsh/site-functions \
        ~/.zsh/completions \
        $fpath\
      )
    '';

    # Custom plugins (sourced after compinit; separate from oh-my-zsh)
    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];

    # ── Init after compinit (main zsh config) ────────────────
    initExtra = ''
      # ── completion tuning ──────────────────────────────────
      zstyle ':completion:*' matcher-list \
        'm:{a-zA-Z}={A-Za-z}' \
        'r:|[._-]=* r:|=*' \
        'l:|=* r:|=*'
      zstyle ':completion:*' menu select
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

      # ── fzf-tab settings ───────────────────────────────────
      zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse --border
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
      zstyle ':fzf-tab:complete:ls:*' fzf-preview 'ls -1 --color=always $realpath'
      zstyle ':fzf-tab:complete:*:*' fzf-preview \
        '[[ -d $realpath ]] && ls -1 --color=always $realpath || [[ -f $realpath ]] && bat --style=numbers --color=always --line-range :50 $realpath 2>/dev/null || echo $realpath'
      zstyle ':fzf-tab:*' switch-group '<' '>'
      zstyle ':fzf-tab:*' fzf-bindings 'enter:accept'

      # ── history substring search keybindings ───────────────
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down
      bindkey '^p' history-substring-search-up
      bindkey '^n' history-substring-search-down

      # ── escape-timeout for vim-mode compatibility ──────────
      export ESCAPE_TIME=100

      # ── zellij auto-attach (local only, never on SSH) ──────
      if [[ -z ''${SSH_CONNECTION:-} && -z ''${SSH_CLIENT:-} ]]; then
        export ZELLIJ_AUTO_ATTACH=true
        export ZELLIJ_AUTO_EXIT=true
      fi

      # ── carapace completions ───────────────────────────────
      if command -v carapace >/dev/null 2>&1; then
        eval "$(carapace _carapace zsh)"
      fi

      # ── pkg function with completion ───────────────────────
      pkg() {
        local env="''${1:-prod}"
        local path="$2"
        local dry_run="''${3:-true}"
        if [[ -z "$path" ]]; then
          echo "Usage: pkg [ENV] SOFTWARE_DIR [DRY_RUN]"
          return 1
        fi
        just ops::package "$env" "$path" "$dry_run"
      }
      _pkg() {
        _arguments \
          '1:environment:(prod staging local)' \
          '2:software directory:_files -/' \
          '3:dry run:(true false)'
      }
      compdef _pkg pkg

      # ── Cheatsheet toggle (darwin only) ────────────────────
      if [[ ''${OSTYPE} == "darwin"* ]] && command -v sketchybar >/dev/null 2>&1; then
        cheat() { sketchybar --set cheatsheet popup.drawing=toggle; }
      fi
    '';

    # ── History settings ──────────────────────────────────────
    history = {
      append = true;
      ignoreAllDups = true;
      size = 10000;
      save = 10000;
      ignorePatterns = [
        "cd"
        "ls"
        "pwd"
      ];
    };

    # ── Shell aliases ─────────────────────────────────────────
    shellAliases = {
      cat = "bat";
      ls = "ls --color=auto";
    };

    # ── Session variables ─────────────────────────────────────
    sessionVariables = {
      EDITOR = "nvim";
      CLICOLOR = "1";
    };
  };

  # ── Darwin-specific: nds function (uses nix interpolation) ──
  config = lib.mkIf (hostName != null && pkgs.stdenv.isDarwin) {
    programs.zsh.shellInit = lib.mkAfter ''
      # ── nds: rebuild + refresh HM session vars in-place ───────
      nds() {
        nh darwin switch --elevation-strategy /usr/bin/sudo "$HOME/.config/nixos-config#${hostName}" "$@" || return $?
        unset __HM_SESS_VARS_SOURCED __HM_ZSH_SESS_VARS_SOURCED
        [ -r "$HOME/.zshenv" ] && . "$HOME/.zshenv"
        print -P "%F{green}nds: HM session vars refreshed%f"
      }
    '';
  };
}
