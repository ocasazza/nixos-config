{ pkgs, ... }:
{
  pre-commit.settings = {
    hooks = {
      # Formatting with treefmt
      treefmt = {
        enable = true;
        name = "treefmt";
        description = "Format all files with treefmt";
        entry =
          let
            treefmt-wrapped = pkgs.writeShellScriptBin "treefmt-wrapped" ''
              export PATH="${
                pkgs.lib.makeBinPath [
                  pkgs.treefmt
                  pkgs.nixfmt-rfc-style
                  pkgs.shfmt
                  pkgs.nodePackages.prettier
                ]
              }:$PATH"
              exec ${pkgs.treefmt}/bin/treefmt --fail-on-change
            '';
          in
          "${treefmt-wrapped}/bin/treefmt-wrapped";
        pass_filenames = false;
      };
      # Nix
      deadnix.enable = true;
      # Conventional commits
      # Disabled because convco depends on dotnet which takes 30+ min to build from source on aarch64-darwin
      # convco.enable = true;
      # YAML
      yamllint = {
        enable = true;
        name = "yamllint";
        entry = "${pkgs.yamllint}/bin/yamllint -c .yamllint.yaml";
        files = "\\.(yml|yaml)$";
        excludes = [ ".github/" ];
      };
      # JSON
      check-json = {
        enable = true;
        name = "check-json";
        entry = "${pkgs.jq}/bin/jq empty";
        files = "\\.json$";
        pass_filenames = true;
      };
    };
  };
}
