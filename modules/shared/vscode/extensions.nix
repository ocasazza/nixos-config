{ pkgs }:

with pkgs.vscode-extensions; [
  # Essential Vim support - Core for Neovim users
  vscodevim.vim

  # Nix support - Essential for this configuration
  bbenoist.nix
  jnoortheen.nix-ide

  # Language support - Using stable Python extension
  # ms-python.python  # Temporarily disabled due to build issues
  # ms-python.pylint  # Temporarily disabled due to build issues
  # ms-python.black-formatter  # Temporarily disabled due to build issues

  # Documentation and writing
  yzhang.markdown-all-in-one

  # Remote development
  ms-vscode-remote.vscode-remote-extensionpack

  # Git and version control
  # eamodio.gitlens

  # Data Science
  # ms-toolsai.datawrangler

  # Themes
  pkief.material-icon-theme
  esbenp.prettier-vscode
  saoudrizwan.claude-dev
] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  # Functional Contrast theme - Good for terminal users
  {
    name = "functional-contrast";
    publisher = "joshumcode";
    version = "2.0.0";
    sha256 = "sha256-PMfGxb4fTww9gi9+U4R5zx8jEwZDJLbWPaswMoQVt6M=";
  }
  # Python support - Temporarily disabled due to hash issues
  # {
  #   name = "python";
  #   publisher = "ms-python";
  #   version = "2024.20.0";
  #   sha256 = "sha256-FAKE-HASH-WILL-BE-UPDATED-ON-FIRST-BUILD";
  # }
]
