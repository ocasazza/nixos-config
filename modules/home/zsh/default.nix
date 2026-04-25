{
  pkgs,
  lib,
  osConfig ? null,
  ...
}:

# zsh: shell + completion + plugins. Snowfall auto-discovers this
# module and applies it to every HM user. We derive `hostName` from
# `osConfig.networking.hostName` when available (every real deploy
# runs HM inside a NixOS/darwin eval) and fall back to `null` so
# pure-HM contexts (if any ever exist) don't crash.
let
  hostName = if osConfig != null then osConfig.networking.hostName else null;
in
{
  programs.zsh = {
    enable = true;
    completionInit = ''
      # extra completion definitions (nix, docker, git, etc.)
      fpath=(${pkgs.zsh-completions}/share/zsh/site-functions $fpath)
      fpath=(${pkgs.nix-zsh-completions}/share/zsh/site-functions $fpath)
      fpath=(~/.zsh/completions $fpath)
      autoload -Uz compinit && compinit
    '';
    initExtra = ''
      # ── zellij auto-attach (local only) ───────────────────────
      # Attach to an existing zellij session (or create one) ONLY when
      # we're in a LOCAL interactive shell — never on SSH. Otherwise
      # every `ssh <host>` lands in the same existing pane as the prior
      # SSH connection, mirroring input/output. $SSH_CONNECTION is set
      # by sshd; absence means this is a local login.
      if [[ -z "''${SSH_CONNECTION:-}" && -z "''${SSH_CLIENT:-}" ]]; then
        export ZELLIJ_AUTO_ATTACH=true
        export ZELLIJ_AUTO_EXIT=true
      fi

      # ── completion system tuning ──────────────────────────────
      # case-insensitive, partial-word, and substring completion
      zstyle ':completion:*' matcher-list \
        'm:{a-zA-Z}={A-Za-z}' \
        'r:|[._-]=* r:|=*' \
        'l:|=* r:|=*'
      # menu-driven completion with selection highlight
      zstyle ':completion:*' menu select
      # group completions by category with headers
      zstyle ':completion:*' group-name '''
      zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
      # colorize file completions like ls
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

      # ── fzf-tab settings ──────────────────────────────────────
      # use tmux popup if available, otherwise default fzf
      zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse --border
      # preview directory contents and file heads
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
      zstyle ':fzf-tab:complete:ls:*' fzf-preview 'ls -1 --color=always $realpath'
      zstyle ':fzf-tab:complete:*:*' fzf-preview \
        '[[ -d $realpath ]] && ls -1 --color=always $realpath || [[ -f $realpath ]] && bat --style=numbers --color=always --line-range :50 $realpath 2>/dev/null || echo $realpath'
      # switch groups with < and >
      zstyle ':fzf-tab:*' switch-group '<' '>'
      # accept selection on enter instead of just inserting
      zstyle ':fzf-tab:*' fzf-bindings 'enter:accept'

      # ── custom functions ──────────────────────────────────────
      # Wrapper for just package command with path completion
      pkg() {
        local env="''${1:-prod}"
        local path="$2"
        local dry_run="''${3:-true}"

        if [[ -z "$path" ]]; then
          echo "Usage: pkg [ENV] SOFTWARE_DIR [DRY_RUN]"
          echo "Example: pkg prod lib/software/appgate/macos"
          echo "Example: pkg prod lib/software/appgate/macos false"
          return 1
        fi

        just ops::package "$env" "$path" "$dry_run"
      }

      # Custom completion for pkg command
      _pkg() {
        local -a args
        args=(
          '1:environment:(prod staging local)'
          '2:software directory:_files -/'
          '3:dry run:(true false)'
        )
        _arguments $args
      }
      compdef _pkg pkg

      # history substring search keybindings (up/down arrows)
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      # ── Cheatsheet toggle ────────────────────────────────────
      # Lives as a sketchybar popup item (`cheatsheet`) on the right
      # side of the bar. `cheat` flips its visibility; click the
      # keyboard glyph in the bar for the same effect.
      if [[ "$OSTYPE" == "darwin"* ]] && command -v sketchybar >/dev/null 2>&1; then
        cheat() { sketchybar --set cheatsheet popup.drawing=toggle; }
      fi
    '';
    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    plugins = [
      {
        # fzf-based tab completion - must load before autosuggestions
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
      {
        # reminds you to use aliases you've already defined
        name = "zsh-you-should-use";
        src = pkgs.zsh-you-should-use;
        file = "share/zsh/plugins/zsh-you-should-use/you-should-use.plugin.zsh";
      }
    ];
    history = {
      append = true; # parallel history until shell exit
      ignoreAllDups = true; # remove previous when duplicate commands run
      ignorePatterns = [
        "cd"
        "ls"
        "pwd"
      ];
    };
    shellAliases = {
      cat = "bat";
      ls = "ls --color=auto";
    }
    # `nds` (nh darwin switch) is darwin-only and depends on hostName,
    # so only emit it when we have a hostName AND we're on darwin.
    // lib.optionalAttrs (hostName != null && pkgs.stdenv.isDarwin) {
      nds = "nh darwin switch --elevation-strategy /usr/bin/sudo ~/.config/nixos-config#${hostName}";
    };
    sessionVariables = {
      EDITOR = "nvim";
      CLICOLOR = "1";
      # Zellij auto-attach is gated in initExtra (below) on NOT being
      # in an SSH session — setting these unconditionally here would
      # make `ssh <host>` land every new shell in the same existing
      # zellij pane, mirroring input/output across terminals.
    };
  };
}
