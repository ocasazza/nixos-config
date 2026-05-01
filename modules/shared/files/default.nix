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
  # .claude/settings.json intentionally NOT managed here. It used to be,
  # but home-manager evaluates `config.programs.claude-code` in its own
  # option namespace where that option isn't declared — so every Mac
  # and desk-nxst-001 ended up with a minimal `{model, skipDangerousModePermissionPrompt}`
  # symlink into /nix/store, silently clobbering the full LiteLLM env
  # block written by the darwin/nixos activation script (which runs
  # first, then is overwritten by home-manager's symlink).
  #
  # The darwin module's `system.activationScripts.claudeCode` (and the
  # nixos module's equivalent) is now the single source of truth; it
  # writes a real file to ~/.claude/settings.json with env +
  # apiKeyHelper when LiteLLM or legacy Vertex is enabled.
  #
  # NOTE: `~/.claude/get-iam-token.sh` is managed by the
  # `modules/darwin/claude-code` module and references
  # `lib.salt.ai.scripts.getIamToken` so the script content is
  # centralized. Do NOT add a second definition here.
}
