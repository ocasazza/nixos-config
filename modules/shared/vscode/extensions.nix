{ pkgs }:

with pkgs.vscode-extensions; [
  vscodevim.vim
  hashicorp.terraform
  yzhang.markdown-all-in-one
  ms-vscode-remote.vscode-remote-extensionpack
  ms-toolsai.datawrangler
  esbenp.prettier-vscode
  pkief.material-icon-theme
] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  {
    name = "claude-dev";
    publisher = "saoudrizwan";
    version = "3.26.7";
    sha256 = "sha256-ACgIIDb5y1kDz7Zm/4MzNj5DLBmpMNo+lM8h/2OyO+M=";
  }
  {
    name = "Nix";
    publisher = "bbenoist";
    version = "1.0.1";
    sha256 = "sha256-qwxqOGublQeVP2qrLF94ndX/Be9oZOn+ZMCFX1yyoH0=";
  }
  {
    name = "Go";
    publisher = "golang";
    version = "0.48.0";
    sha256 = "sha256-W+GsieGOn9UhOB49v/NqsHCoOm4VNaZotipIN2E4N9k=";
  }
  {
    name = "vscode-zig";
    publisher = "ziglang";
    version = "0.6.13";
    sha256 = "sha256-4DYsSGqWa+jbD8tguULFQLdhKluXK8skj9nSst9UX8U=";
  }
  {
    name = "theme-material-theme";
    publisher = "jprestidge";
    version = "1.0.1";
    sha256 = "sha256-nUjskGZf/7Mi3mBAswFfbgdsNNfn5BF/kDZIn8v/BHA=";
  }
  {
    name = "functional-contrast";
    publisher = "joshumcode";
    version = "2.0.0";
    sha256 = "sha256-PMfGxb4fTww9gi9+U4R5zx8jEwZDJLbWPaswMoQVt6M=";
  }
]
