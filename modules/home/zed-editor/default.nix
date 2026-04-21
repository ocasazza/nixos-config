{
  pkgs,
  lib,
  ...
}:

# Zed editor. Snowfall auto-discovers this module and applies it to
# every HM user; the previous call site was the flat
# `modules/shared/home-manager.nix` aggregator (now deleted).
{
  programs.zed-editor = {
    enable = true;
    installRemoteServer = true;
    extensions = [
      "catppuccin"
      "github-actions"
      "nix"
      "opentofu"
    ];
    extraPackages = [
      pkgs.tofu-ls
      pkgs.gemini-cli-bin
    ];
    userSettings = {
      auto_signature_help = true; # not sure about this one yet
      buffer_line_height = "standard";
      buffer_font_size = 16;
      tab_size = 4;
      ui_font_size = 16;
      use_system_prompts = false;
      use_system_path_prompts = false;
      vim_mode = false;
      agent = {
        default_model = {
          provider = "copilot_chat";
          model = "gpt-5-mini";
        };
        # inline_alternatives = [
        # ];
      };
      features = {
        copilot = true;
        edit_prodiction_provider = "copilot";
      };
      gutter = {
        min_line_number_digits = 0;
        line_numbers = true;
      };
      indent_guides = {
        coloring = "indent_aware";
        active_line_width = 2;
        line_width = 1;
      };
      project_panel = {
        hide_root = true;
        hide_hidden = true;
        entry_spacing = "standard";
        default_width = 180.0;
      };
      theme = {
        mode = "system";
        light = "Catppuccin Frappé";
        dark = "Catppuccin Mocha";
      };
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
    };
  };
}
