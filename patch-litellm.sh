#!/usr/bin/env bash
# patch-litellm.sh
# Fixes Qwen3.6-35B tool calling in opencode by disabling parallel function calling in LiteLLM

LITELLM_CONFIG="~/Repositories/schrodinger/nixstation/systems/x86_64-linux/pdx-nxst-001/litellm/providers.nix"
LITELLM_CONFIG_EXPANDED="${HOME}/Repositories/schrodinger/nixstation/systems/x86_64-linux/pdx-nxst-001/litellm/providers.nix"

if [ -f "$LITELLM_CONFIG_EXPANDED" ]; then
  # Insert supports_parallel_function_calling = false; after modelGroup matching qwen
  sed -i '' -e '/modelGroup = "qwen3/a\
    supports_parallel_function_calling = false;\
' "$LITELLM_CONFIG_EXPANDED"
  echo "Patched $LITELLM_CONFIG_EXPANDED"
  echo "Please deploy this configuration to your LiteLLM server to fix the issue."
else
  echo "Could not find $LITELLM_CONFIG_EXPANDED"
fi
