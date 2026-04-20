{
  pkgs,
  ...
}:

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    bashInteractive
    git
    statix
    deadnix
    nh
  ];
  shellHook = ''
    export EDITOR=nvim
  '';
}
