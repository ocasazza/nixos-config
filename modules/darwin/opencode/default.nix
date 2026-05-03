# opencode user-level config: provider registrations + MCP servers.
#
# The opencode binary itself comes from `pkgs.opencode` (stock upstream),
# added to the HM profile in homes/aarch64-darwin/casazza@*/default.nix.
# The Schrodinger fork (with its `programs.opencode` darwin module —
# managedConfig, vertex, apiKeyHelper, telemetry, secrets) was dropped
# 2026-04-30; everything below is configured at the user-level
# ~/.config/opencode/opencode.json which stock opencode reads natively.
#
# Snowfall auto-discovers this module from modules/darwin/opencode/.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = lib.salt.user;
in
{
  # Per-client LiteLLM virtual key + Schrodinger Azure OpenAI key.
  # Both decrypt to single `KEY=value` lines — the home.sessionVariablesExtra
  # below uses `cut -d= -f2-` to peel the value off (same pattern as
  # modules/darwin/claude-code/default.nix:255).
  sops.secrets = {
    litellm-key-opencode-darwin = {
      sopsFile = ../../../secrets/litellm-key-opencode-darwin.yaml;
      format = "yaml";
      key = "litellm_api_key";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
    azure-api-key-opencode-darwin = {
      sopsFile = ../../../secrets/azure-api-key-opencode-darwin.yaml;
      format = "yaml";
      key = "azure_api_key";
      mode = "0440";
      owner = "root";
      group = "staff";
    };
  };

  home-manager.users.${user.name} = {
    # Static (non-secret) provider env. AI-SDK's @ai-sdk/azure provider
    # reads AZURE_RESOURCE_NAME to build endpoint URLs.
    home.sessionVariables = {
      AZURE_RESOURCE_NAME = lib.salt.ai.providers.azure.resourceName;
      GOOGLE_VERTEX_PROJECT = lib.salt.ai.providers.vertex.projectId;
      GOOGLE_VERTEX_LOCATION = lib.salt.ai.providers.vertex.region;
    };

    # Source the per-provider sops secrets at shell init so the user-level
    # opencode config below can resolve `{env:...}` references.
    #
    # Why env: not file:? opencode's `{file:...}` would need a value-only
    # file at activation time, but nix-darwin's activate only runs a
    # hardcoded set of phases (modules/system/activation-scripts.nix) and
    # any post-sops shim would race with sops-install-secrets. zsh's
    # .zshenv fires per-shell, by which time sops has long since
    # decrypted, so this is order-safe and idempotent.
    home.sessionVariablesExtra = ''
      if [ -r "${config.sops.secrets.litellm-key-opencode-darwin.path}" ]; then
        export LITELLM_API_KEY_OPENCODE_DARWIN="$(cut -d= -f2- < "${config.sops.secrets.litellm-key-opencode-darwin.path}")"
      fi
      if [ -r "${config.sops.secrets.azure-api-key-opencode-darwin.path}" ]; then
        export AZURE_API_KEY="$(cut -d= -f2- < "${config.sops.secrets.azure-api-key-opencode-darwin.path}")"
      fi
    '';

    # Managed opencode plugin manifest. Home-manager symlinks this, then
    # the activation script below runs `bun install` so node_modules is
    # populated. We keep the legacy @opencode-ai/plugin (used by some
    # custom skills) and add oh-my-opencode (now oh-my-openagent) for
    # agent orchestration.
    home.file.".config/opencode/package.json".source =
      (pkgs.formats.json { }).generate "opencode-packages.json"
        {
          name = "opencode-plugins";
          version = "1.0.0";
          dependencies = {
            "@opencode-ai/plugin" = "1.3.13";
            "oh-my-opencode" = "3.17.12";
            "@tarquinen/opencode-dcp" = "3.1.9";
          };
        };

    # Minimal oh-my-openagent plugin config: route agents to the LiteLLM
    # smart-routed Qwen3-Coder pool on desk-nxst-001. The proxy fans
    # requests across the full GPU fleet (desk-nxst-001 vLLM + desk-nxst-004
    # vLLM + the gfr/laptop exo MLX backends) and picks the freshest
    # backend per request — substantially better throughput than pinning
    # to one local oMLX instance. Users can override per-project in
    # .opencode/oh-my-openagent.jsonc; see provider.litellm.models below
    # for the full list of pinnable backends.
    home.file.".config/opencode/oh-my-openagent.jsonc".text = ''
      {
        // Default agent model: desk-nxst-001 vLLM (262k context).
        // Override per-session with `/model` to any backend in
        // provider.litellm.models below.
        "agents": {
      "sisyphus": { "model": "litellm/desk-nxst-001-llama-3.3-70b" },
      "prometheus": { "model": "litellm/desk-nxst-001-llama-3.3-70b" },
      "atlas": { "model": "litellm/desk-nxst-001-llama-3.3-70b" },
      "explore": { "model": "litellm/desk-nxst-001-llama-3.3-70b" }
        },
        "disabled_hooks": [],
        "mcp": {
          "websearch": { "enabled": true },
          "context7": { "enabled": true },
          "grep_app": { "enabled": true }
        }
      }
    '';

    home.file.".config/opencode/opencode.json".source =
      (pkgs.formats.json { }).generate "opencode-user.json"
        {
          "$schema" = "https://opencode.ai/config.json";
          # Default model: desk-nxst-001 vLLM (Llama-3.3-70B-AWQ, 16k context).
          # No smart-routing — all backends are explicit aliases below.
          model = "litellm/desk-nxst-001-llama-3.3-70b";
          # Disable the in-TUI auto-update prompt — supervisor-spawned
          # sessions can't dismiss it and end up wedged on the modal.
          autoupdate = false;
          # Flip experimental_telemetry.isEnabled = true on every AI SDK
          # call so each AI SDK span (ai.streamText, ai.doStream, etc.)
          # routes through the OTLP pipeline alongside Effect's own spans.
          experimental.openTelemetry = true;
          # oh-my-openagent (legacy name: oh-my-opencode) multi-agent harness.
          plugin = [
            "oh-my-openagent"
            "@tarquinen/opencode-dcp"
          ];
          enabled_providers = [
            "anthropic"
            "exo"
            "litellm"
            "azure"
            "omlx"
            "google-vertex"
          ];
          # Schrodinger Azure OpenAI (resource: schrodinger-code). API key
          # comes from the sops-decrypted AZURE_API_KEY env var sourced
          # above; resourceName from AZURE_RESOURCE_NAME (set in
          # home.sessionVariables). Deployment IDs are case-sensitive and
          # exact — verified by hitting
          #   POST https://schrodinger-code.openai.azure.com/openai/deployments/<id>/chat/completions?api-version=2024-10-21
          # The display label in /model is `name`; the attribute key is
          # the literal Azure deployment ID.
          provider.azure = {
            npm = "@ai-sdk/azure";
            name = "Schrodinger Azure";
            options = {
              apiKey = "{env:AZURE_API_KEY}";
              resourceName = "{env:AZURE_RESOURCE_NAME}";
            };
            models = {
              "${lib.salt.ai.providers.azure.deployment}" = {
                name = "Kimi K2.6";
                tool_call = true;
                # Kimi K2.6 only supports Azure's Chat Completions endpoint,
                # not the OpenAI Responses API. opencode's azure loader
                # (packages/opencode/src/provider/provider.ts:296) defaults
                # to `sdk.responses(modelID)`; this flag flips it to
                # `sdk.chat(modelID)` for this model only.
                options = {
                  useCompletionUrls = true;
                };
              };
            };
          };
          provider.litellm = {
            npm = "@ai-sdk/openai-compatible";
            name = "Schrodinger LiteLLM";
            options = {
              # Point at desk-nxst-001's Caddy proxy (:8080/litellm); the
              # corporate VPN allows :8080 but not :4000, so Hermes and
              # opencode both route through this shared endpoint.
              baseURL = "${lib.salt.ai.providers.litellm.caddyEndpoint}/v1";
              apiKey = "{env:LITELLM_API_KEY_OPENCODE_DARWIN}";
            };
            # Real model_groups exposed by desk-nxst-001's LiteLLM proxy
            # (verified via `curl localhost:4000/v1/models`). Adding entries
            # here that don't exist on the proxy makes them appear in /model
            # but fail at request time. To add new groups, register them on
            # the LiteLLM side first (nixstation modules/nixos/litellm) and
            # mirror here.
            models = {
              "desk-nxst-001-llama-3.3-70b" = {
                name = "Llama-3.3-70B @ desk-nxst-001 vLLM";
                limit = {
                  context = 16384;
                  output = 4096;
                };
              };
              desk-nxst-004-qwen3-coder = {
                name = "Qwen3-Coder @ desk-nxst-004 vLLM";
                limit = {
                  context = 262144;
                  output = 8192;
                };
              };
              gfr-osx26-02-qwen3-coder = {
                name = "Qwen3-Coder @ GFR exo-02 (MLX 8-bit)";
                limit = {
                  context = 131072;
                  output = 8192;
                };
              };
              gfr-osx26-03-qwen3-coder = {
                name = "Qwen3-Coder @ GFR exo-03 (MLX 8-bit)";
                limit = {
                  context = 131072;
                  output = 8192;
                };
              };
              laptop-qwen3-coder = {
                name = "Qwen3-Coder @ gfr-laptop exo (MLX)";
                limit = {
                  context = 65536;
                  output = 8192;
                };
              };
              gfr-osx26-02-gpt-oss-120b = {
                name = "GPT-OSS 120B @ GFR exo-02 (MLX)";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              gfr-osx26-03-gpt-oss-120b = {
                name = "GPT-OSS 120B @ GFR exo-03 (MLX)";
                limit = {
                  context = 131072;
                  output = 32768;
                };
              };
              coder-cloud-claude = {
                name = "Claude (Vertex passthrough via LiteLLM)";
                limit = {
                  context = 200000;
                  output = 8192;
                };
              };
              embedding = {
                name = "Qwen3-Embedding-0.6B";
                limit = {
                  context = 2048;
                  output = 0;
                };
              };
            };
          };
          # oMLX local inference server (localhost:8000/v1). Apple-Silicon-optimized
          # with continuous batching and tiered KV cache (hot RAM + cold SSD).
          # Models are auto-discovered from ~/.omlx/models. Point any OpenAI-compatible
          # client here for MLX-backed local inference with caching benefits.
          provider.omlx = {
            npm = "@ai-sdk/openai-compatible";
            name = "oMLX Local";
            options = {
              baseURL = lib.salt.ai.providers.omlx.baseURL;
              # oMLX localhost does not require auth by default; the API key
              # field is ignored but ai-sdk requires a non-empty string.
              apiKey = "ollama-not-needed";
            };
            models = {
              qwen3-coder-next = {
                name = "Qwen3-Coder-Next-8bit (MLX local)";
                tool_call = true;
                limit = {
                  context = 32768;
                  output = 8192;
                };
              };
            };
          };
          mcp = {
            obsidian-vault = {
              type = "local";
              command = [
                "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem"
                "/Users/${user.name}/Repositories/ocasazza/obsidian/vault"
              ];
              enabled = true;
            };
          };
        };
  };
}
