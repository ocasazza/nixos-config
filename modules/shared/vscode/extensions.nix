{ pkgs }:

with pkgs.vscode-extensions; [
  # Essential Vim support - Core for Neovim users
  vscodevim.vim

  # Nix support - Essential for this configuration
  bbenoist.nix
  jnoortheen.nix-ide

  # Language support
  ms-python.python
  ms-python.pylint
  ms-python.black-formatter

  # Documentation and writing
  yzhang.markdown-all-in-one

  # Remote development - Great for terminal/SSH workflows
  ms-vscode-remote.vscode-remote-extensionpack

  # Git and version control - Enhanced git for terminal workflow
  eamodio.gitlens

  # Data Science
  ms-toolsai.datawrangler

  # Themes and UI - Terminal-friendly
  pkief.material-icon-theme
  esbenp.prettier-vscode

  # AI assistance - Modern development workflow
  saoudrizwan.claude-dev
] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  # Functional Contrast theme - Good for terminal users
  {
    name = "functional-contrast";
    publisher = "joshumcode";
    version = "2.0.0";
    sha256 = "sha256-PMfGxb4fTww9gi9+U4R5zx8jEwZDJLbWPaswMoQVt6M=";
  }
]
