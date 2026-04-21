{
  user,
  config,
  pkgs,
  ...
}:

let
  # `config.users.users.<n>.home` is a nix-darwin system-level option,
  # so it isn't reachable when this module is invoked from a snowfall
  # home (where `config` is the HM config). Hard-code the macOS path
  # instead — every Mac user's home is /Users/<n>.
  homeDir = "/Users/${user.name}";
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
