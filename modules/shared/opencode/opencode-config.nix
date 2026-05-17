{
  lib,
  pkgs,
  brainDir,
  ...
}:

{
  home.file.".config/opencode/opencode.json".source =
    (pkgs.formats.json { }).generate "opencode.json"
      {
        "$schema" = "https://opencode.ai/config.json";
        model = "litellm/sdgr-glm-5.1";
        autoupdate = false;
        experimental = {
          openTelemetry = true;
        };
        plugin = [
          "oh-my-opencode-slim"
          "@tarquinen/opencode-dcp"
          "./plugins/vertex-proxy.ts"
          "opencode-plugin-openspec"
        ];
        enabled_providers = [
          "litellm"
          "vertex-proxy"
          "sdgr-glm"
          "sdgr-ring"
        ];
        provider = {
          litellm = {
            npm = "@ai-sdk/openai-compatible";
            name = "Schrodinger LiteLLM";
            env = [ "LITELLM_API_KEY" ];
            options = {
              baseURL = "${lib.salt.ai.providers.litellm.caddyEndpoint}/v1";
            };
            models = {
              "qwen3.6-35b-a3b" = {
                name = "Qwen3.6-35B-A3B (load balanced)";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              "qwen3-coder-next" = {
                name = "Qwen3-Coder-Next (load balanced exo)";
                limit = {
                  context = 131072;
                  output = 65536;
                };
              };
              "pdx-nxst-001-qwen3.6-35b-a3b" = {
                name = "Qwen3.6-35B-A3B @ pdx-nxst-001 vLLM";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              "pdx-nxst-002-qwen3.6-35b-a3b" = {
                name = "Qwen3.6-35B-A3B @ pdx-nxst-002 vLLM";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              "pdx-nxst-003-qwen3.6-35b-a3b" = {
                name = "Qwen3.6-35B-A3B @ pdx-nxst-003 vLLM";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              "gfr-osx26-02-qwen3-coder-next" = {
                name = "Qwen3-Coder-Next @ GFR exo-02 (MLX 8-bit)";
                limit = {
                  context = 131072;
                  output = 65536;
                };
              };
              "gfr-osx26-03-qwen3-coder-next" = {
                name = "Qwen3-Coder-Next @ GFR exo-03 (MLX 8-bit)";
                limit = {
                  context = 131072;
                  output = 65536;
                };
              };
              "azure-kimi-k2.6" = {
                name = "Kimi K2.6 (Azure) via LiteLLM";
                tool_call = true;
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              "sdgr-glm-5.1" = {
                name = "GLM-5.1 FP8 (H200) via LiteLLM";
                limit = {
                  context = 202752;
                  output = 32768;
                };
              };
            };
          };
          "sdgr-glm" = {
            npm = "@ai-sdk/openai-compatible";
            name = "Schrödinger GLM";
            options = {
              baseURL = "https://glm-5-1-fp8.autoscale.sdgr.app/v1";
              apiKey = "noauth";
            };
            models = {
              "glm-5.1-fp8" = {
                name = "GLM-5.1 FP8 (H200)";
                limit = {
                  context = 202752;
                  output = 32768;
                };
              };
            };
          };
          "sdgr-ring" = {
            npm = "@ai-sdk/openai-compatible";
            name = "Schrödinger Ring";
            options = {
              baseURL = "https://ring-2-6-1t.autoscale.sdgr.app/v1";
              apiKey = "noauth";
            };
            models = {
              "ring-2.6-1t" = {
                name = "Ring 2.6 1T (H200)";
                reasoningEffort = "xhigh";
                limit = {
                  context = 262144;
                  output = 253952;
                };
              };
            };
          };
          "vertex-proxy" = {
            npm = "@ai-sdk/google-vertex/anthropic";
            name = "Vertex AI (via LiteLLM passthrough)";
            options = {
              apiKey = "placeholder";
              project = lib.salt.ai.providers.vertex.projectId;
              location = lib.salt.ai.providers.vertex.region;
            };
            models = {
              "claude-opus-4-7" = {
                name = "Claude Opus 4.7 (Vertex)";
                tool_call = true;
                limit = {
                  context = 200000;
                  output = 32000;
                };
              };
              "claude-sonnet-4-7" = {
                name = "Claude Sonnet 4.7 (Vertex)";
                tool_call = true;
                limit = {
                  context = 200000;
                  output = 64000;
                };
              };
            };
          };
        };
        instructions = [
          "AGENTS.md"
          "${brainDir}/AGENTS.md"
        ];
      };
}
