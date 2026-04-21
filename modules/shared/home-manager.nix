{
  pkgs,
  lib,
  user,
  hostName ? null,
  ...
}:
{
  zed-editor = {
    enable = true;
    installRemoteServer = true;
    extensions = [
      "catppuccin"
      "github-actions"
      "nix"
      "opentofu"
    ];
    extraPackages = [
      pkgs.tofu-ls
      pkgs.gemini-cli-bin
    ];
    userSettings = {
      auto_signature_help = true; # not sure about this one yet
      buffer_line_height = "standard";
      buffer_font_size = 16;
      tab_size = 4;
      ui_font_size = 16;
      use_system_prompts = false;
      use_system_path_prompts = false;
      vim_mode = false;
      agent = {
        default_model = {
          provider = "copilot_chat";
          model = "gpt-5-mini";
        };
        # inline_alternatives = [
        # ];
      };
      features = {
        copilot = true;
        edit_prodiction_provider = "copilot";
      };
      gutter = {
        min_line_number_digits = 0;
        line_numbers = true;
      };
      indent_guides = {
        coloring = "indent_aware";
        active_line_width = 2;
        line_width = 1;
      };
      project_panel = {
        hide_root = true;
        hide_hidden = true;
        entry_spacing = "standard";
        default_width = 180.0;
      };
      theme = {
        mode = "system";
        light = "Catppuccin Frappé";
        dark = "Catppuccin Mocha";
      };
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
    };
  };

  zsh = {
    enable = true;
    completionInit = ''
      # extra completion definitions (nix, docker, git, etc.)
      fpath=(${pkgs.zsh-completions}/share/zsh/site-functions $fpath)
      fpath=(${pkgs.nix-zsh-completions}/share/zsh/site-functions $fpath)
      fpath=(~/.zsh/completions $fpath)
      autoload -Uz compinit && compinit
    '';
    initExtra = ''
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
    # so only emit it when the caller passed a hostName (i.e. from the
    # darwin HM module). NixOS callers omit hostName → no nds alias.
    // lib.optionalAttrs (hostName != null) {
      nds = "nh darwin switch --elevation-strategy /usr/bin/sudo ~/.config/nixos-config#${hostName}";
    };
    sessionVariables = {
      EDITOR = "nvim";
      CLICOLOR = "1";
      # Zellij auto-start (interactive shells only): attach to existing
      # session if one exists, otherwise create a new one. Exit shell
      # when zellij detaches/exits so Ghostty surfaces close cleanly.
      ZELLIJ_AUTO_ATTACH = "true";
      ZELLIJ_AUTO_EXIT = "true";
    };
  };

  # fzf integration: Ctrl-R (history), Ctrl-T (files), Alt-C (cd)
  fzf = {
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

  starship = {
    enable = true;
    enableZshIntegration = true;
    # these are TOML mappings from https://starship.rs/config
    settings = {
      add_newline = true;
      scan_timeout = 10;
      aws.disabled = true;
      gcloud.disabled = true;

      fill.symbol = " ";
      format = "($nix_shell$container$fill$git_metrics\n)$cmd_duration$hostname$shlvl$shell$env_var$jobs$sudo$username$character";
      right_format = "$directory$vcsh$git_branch$git_commit$git_state$git_status$cmake$python$conda$terraform$rust$memory_usage$custom$status$os$battery$time";
      continuation_prompt = "[▸▹ ](dimmed white)";

      cmd_duration = {
        format = "[$duration](bold yellow)";
      };

      git_branch = {
        symbol = "[△](bold italic bright-blue)";
        format = " [$branch(:$remote_branch)]($style)";
        style = "italic bright-blue";
        only_attached = true;
        truncation_length = 11;
        truncation_symbol = "⋯";
        ignore_branches = [
          "main"
        ];
      };

      git_metrics = {
        disabled = false;
        format = "([+$added](italic dimmed green))([-$deleted](italic dimmed red))";

        ignore_submodules = true;
      };

      git_status = {
        format = "([⎪$ahead_behind$staged$modified$untracked$renamed$deleted$conflicted$stashed⎥]($style))";
        style = "bold dimmed blue";

        ahead = "[▴$count](italic green)|";
        behind = "[▿$count](italic red)|";
        conflicted = "[◪◦](italic bright-magenta)";
        deleted = "[✕](italic red)";
        diverged = "[◇ ▴┤[$ahead_count](regular white)│▿┤[$behind_count](regular white)│](italic bright-magenta)";
        modified = "[●◦](italic yellow)";
        renamed = "[◎◦](italic bright-blue)";
        staged = "[▪┤[$count](bold white)│](italic bright-cyan)";
        stashed = "[◃◈](italic white)";
        untracked = "[◌◦](italic bright-yellow)";
      };

      nix_shell = {
        symbol = "❄";
        format = "[*⎪$state⎪](bold dimmed blue) [$name](italic dimmed white)";

        impure_msg = "[⌽](bold dimmed red)";
        unknown_msg = "[◌](bold dimmed yellow)";
        pure_msg = "[⌾](bold dimmed green)";
      };

      terraform = {
        format = "[🌎⎪$workspace⎪](bold dimmed purple)";
      };
    };
  };

  ghostty = {
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
      command = "/etc/profiles/per-user/${user.name}/bin/zsh";
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

  zellij = {
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

  git = {
    enable = true;
    ignores = [
      ".DS_Store"
      ".swp"
      ".vscode"
    ];
    lfs = {
      enable = true;
    };
    settings = {
      user.name = user.fullName;
      user.email = user.email;
      init.defaultBranch = "main";
      pull.rebase = true;
      rebase.autoStash = true;
      safe.directory = "/Users/${user.name}/src/nixos-config";
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      credential = {
        "https://github.com" = {
          helper = "!gh auth git-credential";
        };
      };
    };
  };

  nushell = {
    enable = true;
    # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
    # configFile.source = ./.config.nu;
    # for editing directly to config.nu
    extraConfig = ''
      let carapace_completer = {|spans|
        carapace $spans.0 nushell ...$spans | from json
      }
      $env.config = {
        show_banner: false,
        completions: {
          case_sensitive: false # case-sensitive completions
          quick: true # set to false to prevent auto-selecting completions
          partial: true # set to false to prevent partial filling of the prompt
          algorithm: "fuzzy" # prefix or fuzzy
          external: {
            # set to false to prevent nushell looking into $env.PATH to find more suggestions
            enable: true
            # set to lower can improve completion performance at the cost of omitting some options
            max_results: 100
            completer: $carapace_completer # check 'carapace_completer'
          }
        }
      }
      $env.PATH = ($env.PATH | split row (char esep) | prepend /home/myuser/.apps | append /usr/bin/env)
    '';
    # shellAliases = {
    #   vi = "hx";
    #   vim = "hx";
    #   nano = "hx";
    # };
  };

  carapace.enable = true;
  carapace.enableNushellIntegration = true;

  gh = {
    enable = true;
    gitCredentialHelper.enable = false; # https://github.com/NixOS/nixpkgs/issues/169115
  };

  direnv = {
    enable = true;
    # nix-direnv caches the result of `nix develop` so subsequent shell
    # activations are near-instant instead of re-evaluating the flake.
    # Without this, every `direnv allow` (and every `cd` into a flake
    # directory) re-runs `nix develop` from scratch, which can hang for
    # minutes when the devshell pulls in heavy packages like Obsidian
    # or TeX Live.
    nix-direnv.enable = true;
    config = {
      global = {
        hide_env_diff = true;
        warn_timeout = 0;
      };
    };
  };
  nvchad = {
    enable = true;
    extraPlugins = ''
      return {
        {"equalsraf/neovim-gui-shim",lazy=false},
        {"lervag/vimtex",lazy=false},
        {"nvim-lua/plenary.nvim"},
        {
          'xeluxee/competitest.nvim',
          dependencies = 'MunifTanjim/nui.nvim',
          config = function() require('competitest').setup() end,
        },
      }
    '';
    extraPackages = with pkgs; [
      bash-language-server
      nixd
      #(python3.withPackages(ps: with ps; [
      #  python-lsp-server
      #  flake8
      #]))
    ];

    chadrcConfig = ''
      local M = {}

      M.base46 = {
        theme = "solarized_osaka",
      }

      M.nvdash = { load_on_startup = true }
    '';
  };

  ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      # Global defaults applied to every host.
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
        identityFile =
          if pkgs.stdenv.hostPlatform.isDarwin then
            "/Users/${user.name}/.ssh/id_ed25519"
          else
            "/home/${user.name}/.ssh/id_ed25519";
      };

      "github.com" = {
        hostname = "github.com";
        identitiesOnly = true;
      };

      "CK2Q9LN7PM-MBA.local CK2Q9LN7PM-MBA.tb".extraOptions.ConnectTimeout = "5";
      "GJHC5VVN49-MBP.local GJHC5VVN49-MBP.tb".extraOptions.ConnectTimeout = "5";

      "desk-nxst-*" = {
        identitiesOnly = true;
        extraOptions = {
          CanonicalizeHostname = "yes";
          CanonicalDomains = "schrodinger.com";
          CanonicalizeMaxDots = "1";
        };
      };

      # ── Home LAN (192.168.1.0/24) ────────────────────────────
      # seir is AppGate-filtered over IPv4 (ZTNA default-deny for
      # non-entitled LAN hosts), so it routes over IPv6 via Bonjour.
      # All other home LAN hosts work fine over IPv4 through AppGate.
      #
      # NOTE: 192.168.1.35 is included as a Host pattern so that muscle
      # memory `ssh olive@192.168.1.35` still works — the HostName override
      # rewrites it to seir.local + forces IPv6 before the connect happens.
      "seir seir.local 192.168.1.35" = {
        hostname = "seir.local";
        user = "olive";
        addressFamily = "inet6";
        identitiesOnly = true;
        identityFile = "/Users/${user.name}/.ssh/olive_id_ed25519";
      };

      # Personal home hosts — all share the olive user + key.
      # This block merges with the per-host HostName blocks below
      # (SSH applies every matching Host pattern).
      "contra rpi5 mm01 mm02 mm03 mm04 mm05 hp01 hp02 hp03" = {
        user = "olive";
        identitiesOnly = true;
        identityFile = "/Users/${user.name}/.ssh/olive_id_ed25519";
      };

      # Raspberry Pi 5
      "rpi5".hostname = "192.168.1.16";

      # contra (cluster head?)
      "contra".hostname = "192.168.1.100";

      # luna — NixOS box, RTX 3090 Ti, vLLM host
      "luna luna.local 192.168.1.57" = {
        hostname = "192.168.1.57";
        user = "casazza";
        identitiesOnly = true;
        identityFile =
          if pkgs.stdenv.isDarwin then
            "/Users/${user.name}/.ssh/id_ed25519"
          else
            "/home/${user.name}/.ssh/id_ed25519";
        extraOptions.ConnectTimeout = "5";
      };

      # HPE iLO BMCs (out-of-band management).
      # Web UI lives on :443, but mpSSH (iLO's smash CLI) on :22 supports
      # power on/off, virtual media, console redirection, etc.
      #
      # iLO's mpSSH only speaks legacy crypto (DH-group14-sha1 + ssh-rsa
      # host keys), which modern OpenSSH disables by default. We re-enable
      # them ONLY for these hosts. User is IPMIUSER (password also IPMIUSER);
      # SSH will prompt for it interactively. Pubkey isn't supported.
      "hp-bmc-*" = {
        user = "IPMIUSER";
        extraOptions = {
          KexAlgorithms = "+diffie-hellman-group14-sha1";
          HostKeyAlgorithms = "+ssh-rsa";
          PubkeyAuthentication = "no";
          PreferredAuthentications = "password,keyboard-interactive";
        };
      };
      "hp-bmc-01 hp-bmc-1".hostname = "192.168.1.101";
      "hp-bmc-02 hp-bmc-2".hostname = "192.168.1.102";
      "hp-bmc-03 hp-bmc-3".hostname = "192.168.1.103";

      # Mac mini cluster (mm01–mm05)
      "mm01".hostname = "192.168.1.111";
      "mm02".hostname = "192.168.1.112";
      "mm03".hostname = "192.168.1.113";
      "mm04".hostname = "192.168.1.114";
      "mm05".hostname = "192.168.1.115";

      # HP servers (hp01–hp03, paired 1:1 with their iLOs above)
      "hp01".hostname = "192.168.1.121";
      "hp02".hostname = "192.168.1.122";
      "hp03".hostname = "192.168.1.123";

      # Dell box (.250) — vague alias since hostname unknown
      "dell".hostname = "192.168.1.250";
    };
  };
}
// import ./vscode { inherit pkgs lib; }
# // import ./zed.nix { inherit pkgs lib; }
