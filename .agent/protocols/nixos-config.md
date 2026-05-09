# nixos-config Project Protocol

Project-specific rules for the **nixos-config** repository. Loaded via the
root `AGENTS.md` (which also points at `.agent/AGENTS.md` for the portable
brain). This file is the source of truth for Nix-side conventions, command
discipline, and the `.dreams/` + `.memories/` workflows that predate
agentic-stack adoption.

## Project Overview

nixos-config is a Nix-managed dotfiles repository. It uses a Nix flake for
development tooling and **snowfall-lib** to organize the repository into
reusable components and data.

The user runs systems / software / data engineering against this repo to
improve IT systems. Conventions:

- DRY (do not repeat yourself); use functional patterns and composition.
- Keep It Simple Stupid; do not rewrite code that already exists.

## Development Environment

- Nix flake (`flake.nix`): dev shells, apps, formatter (`treefmt`). Tracks
  `nixpkgs-unstable`.
- direnv (`.envrc`): loads the flake dev shell automatically via `use flake`.
- Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

### Getting Started

1. Install Nix with flakes enabled.
2. Install direnv and hook it into your shell.
3. `cd` into the repo — direnv activates the dev shell.

## Command Execution Rules

All commands MUST be executed through the Nix flake. Never call tools
(`treefmt`, etc.) directly from the host PATH. This guarantees reproducible,
pinned tool versions.

- **macOS Seatbelt Compliance**: prefix shell commands (especially `nix` and
  `cargo`) with `TMPDIR=.memories/tmp` to avoid "Operation not permitted"
  errors when writing to the system `/tmp`.
- For tasks with a dedicated app: `nix run .#<app>`.
- For ad-hoc commands not covered by an app: `nix develop --command <cmd>`.
- Never rely on globally installed binaries.

### Nix Apps

Project tasks are exposed as Nix apps:

```sh
nix run .#<app_name> -- [args]
```

Examples:

```sh
nix run .#fmt
nix run .#nixos-config -- -m gemma4:26b -p "your prompt here"
```

Discovery: inspect the `apps` attribute set in `flake.nix` (source of truth).

### Ad-hoc Commands

```sh
nix develop --command sops
nix develop --command python3
```

### Nix Helpers (nh)

Use `nh` instead of raw `nix` where it provides a better interface:

| Task            | Command           |
| --------------- | ----------------- |
| Search nixpkgs  | `nh search <pkg>` |
| Garbage collect | `nh clean all`    |

`nh home` and `nh os` / `nh darwin` for Home Manager and NixOS/nix-darwin.

### Adding New Tools

If a tool is missing, do NOT install it globally. Add it to
`devShells.default.packages` in `flake.nix`. For frequent workflows, add a
new entry to the `apps` attrset using the `mkApp` helper.

### pctx (Code Mode)

pctx sits between AI agents and MCP servers, enabling agents to write
TypeScript that runs in a sandboxed Deno environment. Available in the
dev shell.

- Config file: `pctx.json` at repo root
- List upstream MCP servers: `nix run .#pctx-mcp-list`
- Ad-hoc pctx commands: `nix develop --command pctx <subcommand>`
- Add upstream MCP servers: `nix develop --command pctx mcp add <name> <url>`

Code mode tools (when using pctx as an MCP server):

- `pctx.list_functions()` — list available functions
- `pctx.get_function_details()` — get a specific function's schema
- `pctx.execute_typescript()` — execute TypeScript in sandboxed Deno

10-second timeout per execution. No upstream MCP servers configured by
default; add via `pctx mcp add`.

## Architecture and Code Structure

Uses [snowfall-lib](https://snowfall.org/reference/lib/) for the flake
layout. The full skill is at `.agent/skills/snowfall-lib/SKILL.md` (load
when triggers match: snowfall, mkFlake, add module/package/system/home/
overlay/shell/check/template/library, or any "where does this file go"
question).

## Process Mandates

### Definition of Done for Code Changes

Before reporting any code modification task as complete, you MUST verify:

1. **Isolate**: changes were made in a dedicated `git worktree`.
2. **Build**: code compiles without errors (`nix develop --command cargo build` for Rust; equivalent per-language).
3. **Check**: code passes linters and static analysis (`nix develop --command cargo check`).
4. **Test**: relevant unit and integration tests pass (`nix develop --command cargo test`).
5. **State Update**: `.dreams/` or `.memories/` updated to reflect changes.

### Standard Operating Procedure: Code Modification

Follow this exact sequence for any task involving code changes:

1. **Acknowledge & Plan**: confirm understanding, propose a plan.
2. **Isolate**: create a new `git worktree` to contain the changes. State
   the worktree name. Do not proceed until you are inside the worktree.
3. **Implement**: make all code changes and add relevant tests in the
   isolated worktree.
4. **Verify**: execute the Definition of Done checklist. If any step fails,
   return to step 3.
5. **Report**: announce that the work is complete _in the worktree_ and
   ready for review. Await user approval before merging.

## Safety Rules

- NEVER commit or output secrets, credentials, or keys in plaintext.
- ALWAYS commit secrets using [SOPS](https://github.com/getsops/sops).
- NEVER ignore the pre-commit checks.
- When asked to make changes, ALWAYS test them. If new results are
  significantly worse, ask for assistance instead of relying on token spend.

## Code Conventions

- Nix files: format with `nixfmt` (the flake's formatter; via treefmt).
- Keep modules small and composable.
- Use variables and locals over hardcoded values.
- Commit changes after the user approves them — don't wait for an explicit
  `/commit`. Never leave uncommitted changes in the working tree at the
  end of a task. If you wrote code, updated instructions, or created
  files, commit before reporting the task as done.
- Create and commit `.memories/` and `.dreams/` files freely without
  asking — they are first-class project artifacts.
- All agent-generated memory and state belongs in `.memories/` (shared,
  git-committed). Never use agent-specific memory stores
  (e.g., `.claude/memory/`) — all agents must share the same state.
- **Commit Message Formatting**: when using shell tools to commit,
  NEVER use backticks (`` ` ``) in the commit message. Backticks are
  interpreted as command substitutions by the shell and will cause
  errors. Use single quotes (`'`) or double quotes (`"`) for emphasis or
  to denote code/filenames instead.

## Agent Capabilities and Coordination

Agents should leverage their native capabilities:

- **Planning**: for any non-trivial task, create a plan before execution.
- **Check Before Generate**: before running any data-generation task
  (benchmarks, tests, builds), check whether the data already exists.
  Inspect `.memories/` and relevant output directories. "Generate
  missing X" means "find gaps, then fill them" — not "regenerate everything."
- **Task Decomposition**: break work down into discrete, independent chunks.
- **Sub-agents**: for focused, one-directional tasks (research,
  refactoring), delegate to a sub-agent.
- **Context Sharing**: when multi-step tasks require sharing context, use
  a temporary file under `.memories/tmp/` (e.g.,
  `.memories/tmp/<task>.md`). Clean up when the task completes. Never
  write scratch or temp files to `/tmp/`, `.scratch/`, or other locations
  outside the repo — all agent artifacts belong under `.memories/`.
- **pctx Batching**: when performing multiple sequential MCP operations,
  batch them into a single pctx code mode execution to reduce token usage.
- **Token Counting**: use `nix run .#tiktoken -- <file(s)>` to measure the
  token cost of any input. Pipe from stdin for ad-hoc strings. Uses
  cl100k_base (close approximation for Claude). Use this to decide what
  to include in context.

## Dreams and Memories

The project maintains two AI-readable state directories. Their primary
purpose is **token efficiency** — they let agents understand the project
by reading only the small, relevant slices of state they need, rather than
ingesting the entire codebase.

These are SEPARATE from agentic-stack's `.agent/memory/` (working /
episodic / semantic / personal). The agentic-stack memory captures
**agent learnings across sessions**; `.memories/` and `.dreams/` capture
**project state and architecture decisions**. Both are first-class.

### Design Principles

- **Small and numerous**. Each file covers one concern. Prefer many small
  files over few large ones.
- **Linked, not monolithic**. Files reference each other via `links`
  (dreams) or inline references (memories). Agents follow dependency
  chains on demand.
- **Machine-optimized**. Use the `AI-ONLY` header. Compress prose into
  structured fields. Optimize for parsing cost, not human readability.
- **Machine-First Formatting**: use concise, keyword-driven, unambiguous
  formats like key-value pairs. Avoid decorative markdown that adds token
  cost without semantic value.
- **Current, not archival**. Update or delete files as the project
  evolves. Stale files waste tokens.

### `.dreams/` — Plans and Architecture

Dreams are machine-readable plans that encode architecture as DAGs and
sequenced critical paths. Schema in `.dreams/dream-schema.md`.

- One dream per horizon or subsystem.
- Use `links` to connect related dreams.
- Read before implementing to understand DAG position and what is
  blocked/unblocked. Only read the dreams relevant to the work.
- Update when architecture, critical path, risks, or deferred items change.
- Create via `nix run .#dream -- --type plan --horizon <horizon>`.

### `.memories/` — Project State Snapshots

Memories capture state not derivable from code or git history —
decisions, interview state, open questions, inter-session context.

- One memory per concern.
- Cross-reference related memories and dreams by filename.
- Update when decisions are made or questions resolved.
- Delete when superseded by code or no longer relevant.

### When to Update

Updating dreams and memories after completing work is **mandatory, not
optional**. Before reporting a task as done, check whether any dreams or
memories need updating. This is part of the Definition of Done. See
`.memories/dream-update-procedure.md` for detailed triggers and steps.

---

## Claude Code section

Specific to Claude Code. Other harnesses can ignore.

### Agent Coordination Strategy

Two complementary coordination modes:

- **Subagents** for focused, contained, one-directional delegation.
- **Agent teams** for parallel exploration or cross-discipline coordination.

Choose subagents over teams for routine work.

References:

- `.memories/subagent-cost-heuristics.md` — model selection (haiku/sonnet/opus), delegation thresholds, behavioral guardrails.
- `.memories/coordination-rules.md` — team operations (lead role, branch discipline, worktree isolation, post-merge cleanup).
- `.memories/dispatch-examples.md` — code examples.

### Agent Definitions

Reusable agent personas live in `.claude/agents/`. Each defines a role,
model default, and operating instructions. See `.memories/dreamer-role.md`
for detailed dreamer dispatch patterns.

| Agent         | Model                            | Purpose                                                                                            |
| ------------- | -------------------------------- | -------------------------------------------------------------------------------------------------- |
| `dreamer`     | sonnet, opus, or gemini-pro      | Project state guardian. Maintains `.dreams/` and `.memories/`. Never writes source code.           |
| `reviewer`    | sonnet, haiku, or mistral-small  | Code review agent. Reads code, produces structured assessments. Never modifies code.               |
| `implementer` | sonnet, opus, or gemma4:26b      | Code execution agent. Writes code in isolated worktrees. Follows Definition of Done.               |
| `planner`     | sonnet, opus, or qwen3-coder:30b | Implementation planning agent. Produces actionable plans with wave assignments. Never writes code. |

### General Rules

- Clarify wide-scoped prompts before acting. Don't assume scope — confirm it.
- Prefer local models over paid subagents. Use
  `nix run .#nixos-config -- -m <model> -p "<prompt>"` as first choice.
  Reserve paid subagents for tasks where local model output is
  demonstrably inadequate.
- Evaluate local model output by filesystem changes, not raw output.
- After completing a task that used subagents or agent teams, include a
  brief Coordination Summary.

### Local Model Selection & Orchestration

- `.memories/model-dispatch.md` — per-model heuristics, pipeline selection, known failure modes.
- `.memories/local-models.md` — model inventory and benchmark data.

---

## Gemini CLI section

For Gemini CLI agents. Other harnesses can ignore.

- All commands via `run_shell_command` through the Nix flake (e.g.,
  `run_shell_command(command: "nix run .#fmt")`).
- Call Claude: `nix run .#claude -- -p "<prompt>" --dangerously-skip-permissions`
- Call local models: `nix run .#nixos-config -- -m <model> -p "<prompt>"`
- Use `codebase_investigator` for initial analysis, `enter_plan_mode` for
  non-trivial changes, `generalist` sub-agents for focused tasks.
- Use `save_memory` with scope `project` for persistent context.
- The `dreamer` persona maintains `.dreams/` and `.memories/` — never
  writes source code. See `.memories/dreamer-role.md`.
