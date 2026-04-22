{
  pkgs,
  ...
}:

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

  # .claude/settings.json intentionally NOT managed here. It used to be,
  # but home-manager evaluates `config.programs.claude-code` in its own
  # option namespace where that option isn't declared — so every Mac
  # and luna ended up with a minimal `{model, skipDangerousModePermissionPrompt}`
  # symlink into /nix/store, silently clobbering the full LiteLLM env
  # block written by the darwin/nixos activation script (which runs
  # first, then is overwritten by home-manager's symlink).
  #
  # The darwin module's `system.activationScripts.claudeCode` (and the
  # nixos module's equivalent) is now the single source of truth; it
  # writes a real file to ~/.claude/settings.json with env +
  # apiKeyHelper when LiteLLM or legacy Vertex is enabled.
}
