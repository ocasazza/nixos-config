{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = lib.salt.user;
  brainDir = ".agent";

  callFragment =
    hmLib: sub:
    import sub {
      inherit
        lib
        pkgs
        brainDir
        hmLib
        ;
    };
in
{
  home-manager.users.${user.name} =
    { lib, ... }@args:
    let
      hmLib = args.lib;
    in
    lib.mkMerge [
      (callFragment hmLib ./packages.nix)
      (callFragment hmLib ./plugins.nix)
      (callFragment hmLib ./vertex-proxy.nix)
      (callFragment hmLib ./opencode-config.nix)
      (callFragment hmLib ./activation.nix)
      { home.file.".agents/skills".source = config.local.skills.path; }
      { home.file.".agents/commands".source = config.local.commands.path; }
    ];
}
