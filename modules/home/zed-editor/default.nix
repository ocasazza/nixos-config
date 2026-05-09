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
          model = "pdx-nxst-003-qwen3.6-35b-a3b";
        };
      };
      # LiteLLM proxy on pdx-nxst-003 exposed as an OpenAI-compatible
      # provider. API key (OPENAI_API_KEY) is injected into the GUI session
      # at login by the dev.schrodinger.opencode-env LaunchAgent in
      # modules/darwin/opencode/default.nix — no manual keychain setup needed.
      language_models = {
        # LiteLLM router (local vLLM models + cloud routing)
        openai = {
          api_url = "${lib.salt.ai.providers.litellm.caddyEndpoint}/v1";
          available_models = [
            {
              name = "pdx-nxst-003-qwen3.6-35b-a3b";
              display_name = "Qwen3.6-35B-A3B @ pdx-nxst-003 vLLM";
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
            {
              name = "desk-nxst-004-qwen3-embedding";
              display_name = "Qwen3-Embedding-0.6B @ desk-nxst-004";
              max_tokens = 2048;
            }
            {
              name = "pdx-nxst-001-qwen3-32b";
              display_name = "Qwen3-32B @ pdx-nxst-001 vLLM";
              max_tokens = 65536;
            }
            {
              name = "pdx-nxst-002-qwen3-32b";
              display_name = "Qwen3-32B @ pdx-nxst-002 vLLM";
              max_tokens = 65536;
            }
            {
              name = "pdx-nxst-002-qwen3-embedding";
              display_name = "Qwen3-Embedding-0.6B @ pdx-nxst-002";
              max_tokens = 2048;
            }
          ];
        };

        # Anthropic (Claude) via vertex-proxy
        anthropic = {
          api_url = "${lib.salt.ai.providers.vertex.proxyEndpoint}";
          available_models = [
            {
              name = "${lib.salt.ai.models.claudeSonnet}";
              display_name = "Claude Sonnet 4.7 (Vertex)";
              max_tokens = 200000;
            }
            {
              name = "${lib.salt.ai.models.claudeOpus}";
              display_name = "Claude Opus 4.7 (Vertex)";
              max_tokens = 200000;
            }
            {
              name = "${lib.salt.ai.models.claudeHaiku}";
              display_name = "Claude Haiku 4.5 (Vertex)";
              max_tokens = 200000;
            }
          ];
        };

        # Google Gemini via vertex-proxy
        google = {
          api_url = "${lib.salt.ai.providers.vertex.proxyEndpoint}";
          available_models = [
            {
              name = "${lib.salt.ai.models.gemini25Pro}";
              display_name = "Gemini 2.5 Pro (Vertex)";
              max_tokens = 1000000;
            }
            {
              name = "${lib.salt.ai.models.gemini25Flash}";
              display_name = "Gemini 2.5 Flash (Vertex)";
              max_tokens = 1000000;
            }
            {
              name = "${lib.salt.ai.models.gemini3Pro}";
              display_name = "Gemini 3.0 Pro (Vertex)";
              max_tokens = 2000000;
            }
            {
              name = "${lib.salt.ai.models.gemini3Flash}";
              display_name = "Gemini 3.0 Flash (Vertex)";
              max_tokens = 1000000;
            }
          ];
        };

        # Local oMLX server (workstation only)
        ollama = {
          api_url = "${lib.salt.ai.providers.omlx.baseURL}";
          available_models = [
            {
              name = "qwen3-coder";
              display_name = "Qwen3-Coder (Local MLX)";
              max_tokens = 65536;
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
