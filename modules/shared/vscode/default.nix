{ pkgs, lib, ... }:

let
  user = "casazza";
in
{
  vscode = {
    profiles.default = {
      enableUpdateCheck = true;  # Allow VSCode to auto-update
      enableExtensionUpdateCheck = true;  # Allow extension update checks
      # Import modular configurations
      userSettings = import ./settings.nix { inherit pkgs lib user; };
      extensions = import ./extensions.nix { inherit pkgs; };
      keybindings = import ./keybindings.nix;
    };
  };
}
