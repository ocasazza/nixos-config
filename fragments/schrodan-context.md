# Schrodan Rig Context

This fragment is loaded when the active rig is `schrodan`
(`~/Repositories/na-son/schrodan`). It distils the rig-specific rules
from the rig's `AGENTS.md`. Read the source file directly for the full
text — only the load-bearing rules are restated here.

## Toolchain

- Nix flake (`flake.nix`) with direnv-loaded devshell. All commands MUST
  go through Nix — never call host-PATH binaries directly.
- For tasks with a Nix app: `nix run .#<app>`.
- For ad-hoc commands: `nix develop --command <cmd>`.
- Discover apps by inspecting the `apps` attrset in `flake.nix`.

## Definition of Done (code changes)

Before reporting any code modification task as complete, verify:

1. **Isolate** — All changes were made in a dedicated `git worktree`.
2. **Build** — `nix develop --command cargo build` succeeds.
3. **Check** — `nix develop --command cargo check` passes lints and
   static analysis.
4. **Test** — `nix develop --command cargo test` passes.
5. **State Update** — `.dreams/` or `.memories/` updated to reflect the
   changes.

If any step fails, return to implementation; do **not** report done.

## Standard Operating Procedure (code modification)

1. **Acknowledge & Plan** — Confirm the request and propose a plan.
2. **Isolate** — Create a new `git worktree`. State the worktree name.
   Do not implement until you are inside it.
3. **Implement** — All code + test changes inside the worktree.
4. **Verify** — Run the Definition of Done. If any step fails, loop
   back to (3).
5. **Report** — Announce completion _in the worktree_ and await user
   approval before merging.

## Cross-agent dispatch (schrodan-specific)

The rig wraps multiple model CLIs as Nix apps:

```sh
nix run .#schrodan -- -m gpt-oss:20b -p "do something"      # local Ollama
nix run .#schrodan -- -m gemma4:26b -f src/main.rs -p "..."  # with file ctx
nix run .#gemini   -- -y -p "do something"                   # Gemini
nix run .#claude   -- -p "do something" --dangerously-skip-permissions
```

Env defaults: `SCHRODAN_MODEL`, `SCHRODAN_PROMPT`. Default model is
`gpt-oss:20b` if neither is set.

## pctx (code mode)

pctx sandboxes TypeScript execution against upstream MCP servers,
batching tool calls to save tokens. Available in the dev shell.

- Config: `pctx.json` at repo root.
- List upstream servers: `nix run .#pctx-mcp-list`.
- Add an MCP server: `nix develop --command pctx mcp add <name> <url>`.

When performing multiple sequential MCP operations, batch them into a
single pctx code-mode execution.

## `.dreams/` and `.memories/`

These are first-class project artifacts, AI-readable, optimized for
token efficiency. Rules:

- **Small and numerous** — one concern per file.
- **Linked, not monolithic** — use `links` (dreams) or inline
  references (memories).
- **Machine-optimized** — `AI-ONLY` header, key-value structure,
  no decorative markdown.
- **Current, not archival** — delete files when their content moves
  into the code.

Schema for dreams: `.dreams/dream-schema.md`. All scratch / temp files
go under `.memories/tmp/`, never to `/tmp/` or `.scratch/`.

## Safety rules

- NEVER commit secrets, credentials, or keys.
- Always run `nix run .#fmt` before committing Nix files.
- NEVER run multiple Ollama benchmark suites concurrently (GPU
  contention contaminates data 2-10x). Use `nix run .#bench-all` which
  sequences them.
- NEVER use Ollama `:cloud` models — local hardware only.

## Commit conventions

- Commit after user approval, no need to wait for an explicit
  `/commit`.
- Never leave uncommitted changes at end of task.
- `.memories/` and `.dreams/` files commit freely, no approval
  required.
- **Commit messages must not contain backticks** — they shell-substitute.
  Use single or double quotes.
