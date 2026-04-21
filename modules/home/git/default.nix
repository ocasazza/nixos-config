{
  lib,
  ...
}:

# Git config. Snowfall auto-discovers this module and applies it to
# every HM user. `user` (the rich attrset with fullName/email) is
# read from `lib.salt.user`, the snowfall-namespaced canonical
# accessor.
let
  user = lib.salt.user;
in
{
  programs.git = {
    enable = true;
    ignores = [
      ".DS_Store"
      ".swp"
      ".vscode"
    ];
    lfs = {
      enable = true;
    };
    settings = {
      user.name = user.fullName;
      user.email = user.email;
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
}
