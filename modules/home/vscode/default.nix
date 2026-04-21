{ pkgs, lib, ... }:

# VSCode HM config — cross-platform. Snowfall auto-discovers this
# module and applies it to every HM user.
#
# On Darwin we use Microsoft's prebuilt `vscode` (signed binary
# tarball, builds cleanly through nixpkgs).
#
# On Linux, `pkgs.vscode` from nixpkgs transitively requires `xcbuild`
# to compile, and `xcbuild` (a macOS Xcode-build-system port) fails
# to compile against modern glibc/C++17 on x86_64-linux. We swap to
# `vscode-fhs` (the same Microsoft binary, wrapped with an FHS
# environment so plugins find their expected `/lib`/`/usr` paths).
{
  programs.vscode = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.vscode else pkgs.vscode-fhs;
    profiles.default = {
      enableUpdateCheck = true; # Allow VSCode to auto-update
      enableExtensionUpdateCheck = true; # Allow extension update checks
      # Import modular configurations
      userSettings = import ./settings.nix { inherit pkgs; };
      extensions = import ./extensions.nix { inherit pkgs; };
      keybindings = import ./keybindings.nix;
    };
  };
}
