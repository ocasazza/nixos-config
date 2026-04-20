{ pkgs, ... }:

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
  # internal vertex-proxy. `exec` (instead of `echo $(...)`) makes
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

  # Claude Code settings — vertex-proxy + helper. Managed declaratively
  # so this configuration is reproduced on every new machine via
  # `nh darwin switch` instead of being lost / re-fixed by hand.
  ".claude/settings.json".text = builtins.toJSON {
    apiKeyHelper = "~/.claude/get-iam-token.sh";
    env = {
      CLAUDE_CODE_USE_VERTEX = "1";
      CLOUD_ML_REGION = "us-east5";
      ANTHROPIC_VERTEX_PROJECT_ID = "vertex-code-454718";
      CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
      ANTHROPIC_VERTEX_BASE_URL = "https://vertex-proxy.sdgr.app/v1";
      CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
    };
    model = "claude-opus-4-7";
    skipDangerousModePermissionPrompt = true;
  };
}
