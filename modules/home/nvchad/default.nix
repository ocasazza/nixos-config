{
  pkgs,
  ...
}:

# NvChad-based neovim distribution. Requires `inputs.nix4nvchad.homeManagerModule`
# which is imported by every `homes/<arch>/casazza*/default.nix`. Snowfall
# auto-discovers this module and applies it to every HM user.
{
  programs.nvchad = {
    enable = true;
    extraPlugins = ''
      return {
        {"equalsraf/neovim-gui-shim",lazy=false},
        {"lervag/vimtex",lazy=false},
        {"nvim-lua/plenary.nvim"},
        {
          'xeluxee/competitest.nvim',
          dependencies = 'MunifTanjim/nui.nvim',
          config = function() require('competitest').setup() end,
        },
      }
    '';
    extraPackages = with pkgs; [
      bash-language-server
      nixd
      #(python3.withPackages(ps: with ps; [
      #  python-lsp-server
      #  flake8
      #]))
    ];

    chadrcConfig = ''
      local M = {}

      M.base46 = {
        theme = "solarized_osaka",
      }

      M.nvdash = { load_on_startup = true }
    '';
  };
}
