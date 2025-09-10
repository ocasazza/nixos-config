{
  pkgs,
  lib,
  user,
  ...
}:
{
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
      TFENV_CONFIG_DIR = "$HOME/.local/share/tfenv";
      PATH = "$HOME/.tfenv/bin:$PATH";
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
    package = null;
    settings = {
      font-size = 14;
      font-family = "JetBrainsMono Nerd Font Mono";
      theme = "MaterialDarker";
      cursor-style = "block";
      shell-integration-features = "no-cursor";
      clipboard-paste-protection = false;
      copy-on-select = true;
      term = "xterm-256color";
      macos-titlebar-proxy-icon = "hidden";
      config-file = "~/.config/ghostty/extra"; # for testing shaders atm
      command = "/etc/profiles/per-user/casazza/bin/zsh";
      keybind = [
        "cmd+shift+d=close_surface"
        "cmd+shift+o=new_split:down"
        "cmd+shift+e=new_split:right"
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

  nvf = {
    enable = true;
    settings = {
      vim = {
        autocomplete.nvim-cmp.enable = true;
        autopairs.nvim-autopairs.enable = true;
        comments.comment-nvim.enable = true;
        enableLuaLoader = true;
        git.gitsigns.enable = true;
        mini.tabline.enable = true;
        statusline.lualine.enable = true;
        vimAlias = true;
        filetree.nvimTree = {
          enable = true;
          mappings.toggle = " t";
          setupOpts.hijack_cursor = true;
        };
        languages = {
          enableTreesitter = true;
          enableFormat = true;
          bash.enable = true;
          markdown.enable = true;
          nix.enable = true;
          python.enable = true;
          terraform.enable = true;
          yaml.enable = true;
        };
        lsp = {
          enable = true;
        };
        theme = {
          enable = true;
          name = "solarized";
          style = "dark";
        };
        clipboard = {
          enable = true;
          registers = "unnamedplus";
        };
      };
    };
  };

  #vim = {
  #  enable = true;
  #  plugins = with pkgs.vimPlugins; [
  #    vim-airline
  #    vim-airline-themes
  #    vim-startify
  #    vim-tmux-navigator
  #  ];
  #  settings = {
  #    ignorecase = true;
  #  };
  #  extraConfig = ''
  #    "" General
  #    set number
  #    set history=1000
  #    set nocompatible
  #    set modelines=0
  #    set encoding=utf-8
  #    set scrolloff=3
  #    set showmode
  #    set showcmd
  #    set hidden
  #    set wildmenu
  #    set wildmode=list:longest
  #    set cursorline
  #    set ttyfast
  #    set nowrap
  #    set ruler
  #    set backspace=indent,eol,start
  #    set laststatus=2
  #    set clipboard=autoselect

  #    " Dir stuff
  #    set nobackup
  #    set nowritebackup
  #    set noswapfile
  #    set backupdir=~/.config/vim/backups
  #    set directory=~/.config/vim/swap

  #    "" Whitespace rules
  #    set tabstop=8
  #    set shiftwidth=2
  #    set softtabstop=2
  #    set expandtab

  #    "" Searching
  #    set incsearch
  #    set gdefault

  #    "" Statusbar
  #    set nocompatible " Disable vi-compatibility
  #    set laststatus=2 " Always show the statusline
  #    let g:airline_theme='seoul256'
  #    let g:airline_powerline_fonts = 1

  #    "" Local keys and such
  #    let mapleader=","
  #    let maplocalleader=" "

  #    "" Change cursor on mode
  #    :autocmd InsertEnter * set cul
  #    :autocmd InsertLeave * set nocul

  #    "" File-type highlighting and configuration
  #    syntax on
  #    filetype on
  #    filetype plugin on
  #    filetype indent on

  #    "" Paste from clipboard
  #    nnoremap <Leader>, "+gP

  #    "" Copy from clipboard
  #    xnoremap <Leader>. "+y

  #    "" Move cursor by display lines when wrapping
  #    nnoremap j gj
  #    nnoremap k gk

  #    "" Map leader-q to quit out of window
  #    nnoremap <leader>q :q<cr>

  #    "" Move around split
  #    nnoremap <C-h> <C-w>h
  #    nnoremap <C-j> <C-w>j
  #    nnoremap <C-k> <C-w>k
  #    nnoremap <C-l> <C-w>l

  #    let g:startify_lists = [
  #      \ { 'type': 'dir',       'header': ['   Current Directory '. getcwd()] },
  #      \ { 'type': 'sessions',  'header': ['   Sessions']       },
  #      \ { 'type': 'bookmarks', 'header': ['   Bookmarks']      }
  #      \ ]

  #    let g:startify_bookmarks = [
  #      \ '~/.local/share/src',
  #      \ ]

  #  '';
  #};

  ssh = {
    enable = true;
    matchBlocks = {
      "*" = {
        extraOptions = lib.mkMerge [
          (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            IdentityFile = "/home/${user.name}/.ssh/id_ed25519";
          })
          (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
            IdentityFile = "/Users/${user.name}/.ssh/id_ed25519";
          })
        ];
      };
      "github.com" = {
        user = "admin";
        hostname = "github.com";
        identitiesOnly = true;
      };
    };
    enableDefaultConfig = false;
  };
}
// import ./vscode { inherit pkgs lib; }
