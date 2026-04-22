{
  config,
  pkgs,
  user,
  ...
}:

let
  # Mirror whatever the claude-code module has been set to in the host
  # config. Three shapes, mirrored from modules/{darwin,nixos}/claude-code:
  #   1. litellm.enable && cloudPassthrough = true  -> ANTHROPIC_BASE_URL = <ep>/vertex/v1
  #   2. litellm.enable && cloudPassthrough = false -> ANTHROPIC_BASE_URL = <ep>/v1
  #   3. legacy vertex                             -> CLAUDE_CODE_USE_VERTEX + vertex URLs
  #
  # The activation script in the darwin claude-code module also writes
  # this file; home-manager's home.file happens first on activation, so
  # the activation-script copy is authoritative. Keeping the HM shape
  # aligned avoids flip-flop on `home-manager switch` mid-session.
  ccCfg = config.programs.claude-code or { };
  ccEnable = ccCfg.enable or false;
  litellmEnable = ccEnable && (ccCfg.litellm.enable or false);
  legacyVertexEnable = ccEnable && (ccCfg.vertex.enable or false) && !litellmEnable;

  litellmEnv =
    if (ccCfg.litellm.cloudPassthrough or true) then
      {
        ANTHROPIC_BASE_URL = "${ccCfg.litellm.endpoint or "http://luna.local:4000"}/vertex/v1";
        CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
      }
    else
      {
        ANTHROPIC_BASE_URL = "${ccCfg.litellm.endpoint or "http://luna.local:4000"}/v1";
      };

  legacyVertexEnv = {
    CLAUDE_CODE_USE_VERTEX = "1";
    CLOUD_ML_REGION = ccCfg.vertex.region or "us-east5";
    ANTHROPIC_VERTEX_PROJECT_ID = ccCfg.vertex.projectId or "";
    CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
    ANTHROPIC_VERTEX_BASE_URL = ccCfg.vertex.baseURL or "";
    CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
  };

  ccEnv =
    if litellmEnable then
      litellmEnv
    else if legacyVertexEnable then
      legacyVertexEnv
    else
      { };

  # apiKeyHelper is emitted whenever the cloud path is active — either
  # legacy-vertex OR litellm+cloudPassthrough. litellm+!cloudPassthrough
  # skips it (the wrapper reads the virtual key from sops at run time).
  ccHelperActive = legacyVertexEnable || (litellmEnable && (ccCfg.litellm.cloudPassthrough or true));

  ccSettings = {
    model = ccCfg.model or "claude-opus-4-7";
  }
  // (if ccEnv != { } then { env = ccEnv; } else { })
  // (if ccHelperActive then { apiKeyHelper = "~/.claude/get-iam-token.sh"; } else { })
  // {
    skipDangerousModePermissionPrompt = true;
  };

  _ = user;
in
{
  ".tfenv".source = pkgs.fetchFromGitHub {
    owner = "tfutils";
    repo = "tfenv";
    rev = "39d8c27";
    sha256 = "h5ZHT4u7oAdwuWpUrL35G8bIAMasx6E81h15lTJSHhQ=";
  };

  ".config/ghostty/extra".text = "";

  # ── Claude Code ─────────────────────────────────────────────────────────
  # apiKeyHelper script: fetches a fresh GCP identity token for the
  # internal vertex-proxy (or for LiteLLM's /vertex passthrough, which
  # forwards it unchanged). `exec` (instead of `echo $(...)`) makes
  # failures surface to Claude Code with the real underlying error
  # message instead of the misleading "did not return a value".
  ".claude/get-iam-token.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec gcloud auth print-identity-token
    '';
  };

  # Claude Code settings — rendered dynamically from programs.claude-code
  # options so flipping litellm.enable = true (or reverting to legacy
  # vertex) regenerates the right env block without hand-editing JSON.
  # Managed declaratively so this configuration is reproduced on every
  # new machine via `nh darwin switch` instead of being lost / re-fixed
  # by hand.
  ".claude/settings.json".text = builtins.toJSON ccSettings;
}
