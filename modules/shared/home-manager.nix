{
  pkgs,
  lib,
  user,
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
    };
    sessionVariables = {
      EDITOR = "nvim";
      # tfenv stuff
      # TFENV_CONFIG_DIR = "$HOME/.local/share/tfenv";
      # PATH = "$HOME/.tfenv/bin:$PATH";
    };
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
      # config-file = "~/.config/ghostty/extra"; # for testing shaders atm
      command = "/etc/profiles/per-user/${user.name}/bin/zsh";
      keybind = [
        "cmd+shift+d=close_surface"
        "cmd+shift+e=new_split:down"
        "cmd+shift+o=new_split:right"
      ];
    };
  };

  git = {
    enable = true;
    userName = user.fullName;
    userEmail = user.email;
    ignores = [
      ".DS_Store"
      ".swp"
      ".vscode"
    ];
    lfs = {
      enable = true;
    };
    extraConfig = {
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
      nodePackages.bash-language-server
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
    matchBlocks."*" = {
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
    };
    extraConfig = lib.mkMerge [
      ''
        Host github.com
          Hostname github.com
          IdentitiesOnly yes

        Host desk-nxst-*
          CanonicalizeHostname yes
          CanonicalDomains schrodinger.com
          CanonicalizeMaxDots 1
          IdentitiesOnly yes
      ''
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux ''
        IdentityFile /home/${user.name}/.ssh/id_ed25519
      '')
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin ''
        IdentityFile /Users/${user.name}/.ssh/id_ed25519
      '')
    ];
  };
}
// import ./vscode { inherit pkgs lib; }
# // import ./zed.nix { inherit pkgs lib; }
