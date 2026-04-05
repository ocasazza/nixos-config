{ pkgs, ... }:

{
  ".tfenv".source = pkgs.fetchFromGitHub {
    owner = "tfutils";
    repo = "tfenv";
    rev = "39d8c27";
    sha256 = "h5ZHT4u7oAdwuWpUrL35G8bIAMasx6E81h15lTJSHhQ=";
  };

  ".config/ghostty/extra".text = ''
    # Extra Ghostty configuration for testing custom shaders and settings
    # This file is managed by NixOS and can be edited here without full rebuilds

    # Add any experimental shader settings or overrides here
    # For example:
    # background-opacity = 0.90
    # background-blur-radius = 30
  '';
}
