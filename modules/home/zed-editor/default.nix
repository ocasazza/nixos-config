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
          provider = "openai";
          model = "desk-nxst-001-qwen3.6-35b-a3b";
        };
      };
      # LiteLLM proxy on desk-nxst-001 exposed as an OpenAI-compatible
      # provider. API key (OPENAI_API_KEY) is injected into the GUI session
      # at login by the dev.schrodinger.opencode-env LaunchAgent in
      # modules/darwin/opencode/default.nix — no manual keychain setup needed.
      language_models = {
        openai = {
          api_url = "${lib.salt.ai.providers.litellm.caddyEndpoint}/v1";
          available_models = [
            {
              name = "desk-nxst-001-qwen3.6-35b-a3b";
              display_name = "Qwen3.6-35B-A3B @ desk-nxst-001 vLLM";
              max_tokens = 32768;
            }
            {
              name = "desk-nxst-004-qwen3-32b";
              display_name = "Qwen3-32B @ desk-nxst-004 vLLM";
              max_tokens = 65536;
            }
            {
              name = "gfr-osx26-02-qwen3-coder-next";
              display_name = "Qwen3-Coder-Next @ GFR exo-02 (MLX)";
              max_tokens = 131072;
            }
            {
              name = "gfr-osx26-03-qwen3-coder-next";
              display_name = "Qwen3-Coder-Next @ GFR exo-03 (MLX)";
              max_tokens = 131072;
            }
            {
              name = "laptop-qwen3-coder";
              display_name = "Qwen3-Coder-480B @ laptop exo (MLX)";
              max_tokens = 65536;
            }
            {
              name = "gfr-osx26-02-gpt-oss-120b";
              display_name = "GPT-OSS 120B @ GFR exo-02 (MLX)";
              max_tokens = 131072;
            }
            {
              name = "gfr-osx26-03-gpt-oss-120b";
              display_name = "GPT-OSS 120B @ GFR exo-03 (MLX)";
              max_tokens = 131072;
            }
          ];
        };
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
