{
  user,
  config,
  pkgs,
  ...
}:

let
  homeDir = config.users.users.${user.name}.home;
  #xdg_configHome = "${homeDir}/.config";
  #xdg_stateHome = "${homeDir}/.local/state";
  xdg_dataHome = "${homeDir}/.local/share";
in
{
  # tfenv is picky about ggrep being present on osx
  "${xdg_dataHome}/bin/ggrep" = {
    source = "${pkgs.gnugrep}/bin/grep";
    executable = true;
  };
  # The cheatsheet now lives as a sketchybar popup (see
  # hosts/darwin/default.nix → services.sketchybar). \u00dcbersicht widget
  # was retired to avoid running two desktop-widget engines side-by-side.
}
