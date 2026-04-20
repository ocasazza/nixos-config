{
  lib,
  inputs,
  ...
}:

let
  user = lib.salt.user;
in
{
  imports = [
    ../../../hosts/nixos
  ];

  # home-manager user config
  home-manager.users.${user.name} = import ../../../modules/nixos/home-manager.nix;

  environment.systemPackages = [
    inputs.ghostty.packages.x86_64-linux.default
  ];
}
