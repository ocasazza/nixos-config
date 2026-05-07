# AGENTS.md

Shared agent instructions for all AI coding agents (collectively referred to as "nixos-config"). Referred to as "agent instructions" or just "instructions" for short. `CLAUDE.md` and `GEMINI.md` are symlinks to this file — agent-specific sections are at the end.

## Project Overview

nixos-config is a Nix-managed dotfiles repository. It uses a Nix flake for development tooling and snowfall lib to organize the repository into reuseable components and data.

Day to day I utilize systems, software and data engineering techniques to improve IT systems and this repository reflects these needs.

I strive for DRY (do not repeat yourself), ideomatic code that utilize functional patterns and composition to minimize and share code. Keep it simple stupid. Do not rewrite code that already exists.

## Development Environment

- Nix flake (`flake.nix`): Defines dev shells, apps, and the formatter (`treefmt`). Tracks nixpkgs-unstable`.
- direnv (`.envrc`): Loads the flake dev shell automatically via `use flake`.
- Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

### Getting Started

1. Install Nix with flakes enabled.
2. Install direnv and hook it into your shell.
3. `cd` into the repo — direnv will activate the dev shell.

## Command Execution Rules

All commands MUST be executed through the Nix flake. Never call tools (`treefmt`, etc.) directly from the host PATH. This guarantees reproducible, pinned tool versions.

- **macOS Seatbelt Compliance**: All shell commands (especially `nix` and `cargo`) SHOULD be prefixed with `TMPDIR=.memories/tmp` to avoid "Operation not permitted" errors when writing to the system `/tmp`.
- For tasks with a dedicated app: use `nix run .#<app>`.
- For ad-hoc commands not covered by an app: use `nix develop --command <cmd>`.
- Never rely on globally installed binaries.

# Architecture and Code Structure

Uses (snowfall-lib)[https://snowfall.org/reference/lib/] to structure the repository. See @.claude/skills/snowfall-lib/SKILL.md whenever you are about to:

- Create, update or move a package, module, overlay, system, home, shell,
  check, template, or library file.
- Touch `mkFlake` / `mkLib` arguments in `flake.nix` (namespace,
  channels-config, alias, overlays, systems.modules,
  systems.hosts.<host>, homes.modules, homes.users.<user@host>,
  outputs-builder, snowfall.root, snowfall.meta).

### Nix Apps

Project tasks are exposed as Nix apps and can be run using a consistent pattern.

Execution Pattern:

```sh
nix run .#<app_name> -- [args]
```

Examples:

- Simple app (no args):
  ```sh
  nix run .#fmt
  ```
- App with arguments:
  ```sh
  nix run .#nixos-config -- -m gemma4:26b -p "your prompt here"
  ```

Discovery:
To discover all available `<app_name>` options, inspect the `apps` attribute set within `flake.nix`, which is the source of truth.

### Ad-hoc Commands

For commands not covered by an app, run them inside the dev shell:

```sh
nix develop --command sops
nix develop --command python3
```

### Nix Helpers (nh)

Use `nh` instead of raw `nix` commands where it provides a better interface:

| Task            | Command           |
| --------------- | ----------------- |
| Search nixpkgs  | `nh search <pkg>` |
| Garbage collect | `nh clean all`    |

`nh` will also be used for Home Manager (`nh home`) and NixOS/nix-darwin (`nh os`/`nh darwin`) operations as the project adds managed environments for subagents and processes.

### Adding New Tools

If a tool is missing, do not install it globally. Add it to `devShells.default.packages` in `flake.nix`. For frequently-used workflows, add a new entry to the `apps` attrset in `flake.nix` using the `mkApp` helper.

### pctx (Code Mode)

pctx is an execution framework that sits between AI agents and MCP servers, enabling agents to write TypeScript that runs in a sandboxed Deno environment. It's available in the dev shell via the flake.

- Config file: `pctx.json` at repo root
- List upstream MCP servers: `nix run .#pctx-mcp-list`
- Ad-hoc pctx commands: `nix develop --command pctx <subcommand>`
- Adding upstream MCP servers: `nix develop --command pctx mcp add <name> <url>`

Code mode tools (when using pctx as an MCP server):

- `pctx.list_functions()` — list available functions from upstream MCP servers
- `pctx.get_function_details()` — get detailed schema for a specific function
- `pctx.execute_typescript()` — execute TypeScript code in a sandboxed Deno environment

Code runs in a sandboxed Deno environment with a 10-second timeout. Currently no upstream MCP servers are configured; add them via `nix develop --command pctx mcp add <name> <url>`.

## Process Mandates

### Definition of Done for Code Changes

Before reporting any code modification task as complete, you MUST verify the following steps have been completed and were successful:

1.  Isolate: All changes were made in a dedicated `git worktree`.
2.  Build: The code compiles without errors (`nix develop --command cargo build`).
3.  Check: The code passes all linters and static analysis (`nix develop --command cargo check`).
4.  Test: All relevant unit and integration tests pass (`nix develop --command cargo test`).
5.  State Update: `.dreams/` or `.memories/` have been updated to reflect the changes.

### Standard Operating Procedure: Code Modification

You MUST follow this exact sequence for any task involving code changes (e.g., new features, bug fixes, refactoring).

1.  Acknowledge & Plan: Confirm you understand the request and propose a plan.
2.  Isolate: Create a new `git worktree` to contain the changes. State the name of the worktree you are creating. Do not proceed to step 3 until you are in the worktree.
3.  Implement: Make all code changes and add relevant tests within the isolated worktree.
4.  Verify: Execute the "Definition of Done" checklist. If any step fails, return to step 3. Do not proceed to step 5 until all checks pass.
5.  Report: Announce that the work is complete _in the worktree_ and ready for review. Await user approval before merging.

## Safety Rules

- NEVER commit or output secrets, credentials, or keys in plaintext.
- ALWAYS commit secrets using [SOPS Secrets](https://github.com/getsops/sops).
- NEVER ignore the pre-commit checks.
- When asked to make changes ALWAYS test them. If new results are significantly worse ask for assistance instead of relying on token spend.

## Code Conventions

- Nix files: format with `nixfmt` (the flake's formatter).
- Keep modules small and composable.
- Use variables and locals over hardcoded values.
- Commit changes after the user approves them — don't wait for an explicit `/commit`. Never leave uncommitted changes in the working tree at the end of a task. If you wrote code, updated instructions, or created files, commit before reporting the task as done.
- Create and commit `.memories/` and `.dreams/` files freely without asking — they are first-class project artifacts.
- All agent-generated memory and state belongs in `.memories/` (shared, git-committed). Never use agent-specific memory stores (e.g., `.claude/memory/`) — all agents must share the same state.
- **Commit Message Formatting**: When using `run_shell_command` to commit, NEVER use backticks (`` ` ``) in the commit message. Backticks are interpreted as command substitutions by the shell and will cause errors. Use single quotes (`'`) or double quotes (`"`) for emphasis or to denote code/filenames instead.
  - `commit_message_good_example: 'feat: Update "ollama_provider.rs" with new options'`
  - `commit_message_bad_example: 'feat: Update `ollama_provider.rs` with new options'`

## Agent Capabilities and Coordination

Agents should leverage their native capabilities to increase efficiency and safety. Refer to the agent-specific sections below for details on available tools and features.

- Planning: For any non-trivial task, create a plan before execution.
- Check Before Generate: Before running any data-generation task (benchmarks, tests, builds), first check whether the data already exists. Use a haiku subagent or direct file read to inspect `.memories/` and relevant output directories. Only generate data that is actually missing. "Generate missing X" means "find gaps, then fill them" — not "regenerate everything."
- Task Decomposition: Break work down into discrete, independent chunks.
- Sub-agents: For focused, one-directional tasks (e.g., research, refactoring), delegate to a sub-agent.
- Context Sharing: When multi-step tasks require sharing context, use a temporary file under `.memories/tmp/` (e.g., `.memories/tmp/<task>.md`). Clean up temporary files when the task is complete. Never write scratch or temp files to `/tmp/`, `.scratch/`, or other locations outside the repo — all agent artifacts belong under `.memories/`.
- pctx Batching: When performing multiple sequential MCP operations, batch them into a single pctx code mode execution to reduce token usage.
- Token Counting: Use `nix run .#tiktoken -- <file(s)>` to measure the token cost of any input (files, prompts, context). Pipe from stdin for ad-hoc strings. Uses cl100k_base encoding (close approximation for Claude). Use this to make informed decisions about what to include in context, whether a file should be split, or whether a memory/dream is too large.

## Dreams and Memories

The project maintains two AI-readable state directories. Their primary purpose is token efficiency — they let agents understand the project by reading only the small, relevant slices of state they need, rather than ingesting the entire codebase. They are first-class project artifacts, not optional extras.

### Design Principles

- Small and numerous. Each file should cover one concern. Prefer many small files over few large ones. An agent working on the provider system should be able to read just the provider-related dream/memory without pulling in TUI or networking context.
- Linked, not monolithic. Files reference each other via `links` (dreams) or inline references (memories) so agents can follow dependency chains on demand. The graph structure means an agent can start at any node and pull in only what's connected.
- Machine-optimized. Use the `AI-ONLY` header. Compress prose into structured fields. Optimize for parsing cost, not human readability.
- **Machine-First Formatting**: Optimize for machine comprehension, not human readability. Use concise, keyword-driven, unambiguous formats like key-value pairs. Avoid decorative markdown (e.g., `#` headers, `*` lists) that adds token cost without semantic value for parsers.
- Current, not archival. Update or delete files as the project evolves. Stale files waste tokens. If a fact is now in the code, remove it from the memory.

### `.dreams/` — Plans and Architecture

Dreams are machine-readable plans that encode architecture as DAGs and sequenced critical paths. Schema is defined in `.dreams/dream-schema.md`.

- One dream per horizon or subsystem. Don't pack unrelated plans into one file. A dream for the provider subsystem should be separate from a dream for the TUI.
- Use `links` to connect related dreams (e.g., v0 links to v1, a subsystem dream links to the parent plan). This lets agents traverse only the relevant subgraph.
- Read before implementing to understand DAG position and what is blocked/unblocked. Only read the dreams relevant to the work — don't load all dreams for a focused task.
- Update when the architecture, critical path, risks, or deferred items change.
- Create via `nix run .#dream -- --type plan --horizon <horizon>` when a new planning horizon is needed.

### `.memories/` — Project State Snapshots

Memories capture state not derivable from code or git history — decisions, interview state, open questions, inter-session context.

- One memory per concern. A decision about provider interfaces, an open question about embedding runtimes, and the PRD interview state should be separate files.
- Cross-reference related memories and dreams by filename so agents can follow links.
- Update when decisions are made or open questions are resolved.
- Delete when a memory is superseded by code or no longer relevant. Every file has a token cost — dead files are waste.

### When to Update

Updating dreams and memories after completing work is mandatory, not optional. Before reporting a task as done, check whether any dreams or memories need updating. This is part of the definition of done. See `.memories/dream-update-procedure.md` for detailed triggers and steps.

---

## Claude Code

This section contains instructions specific to Claude Code. Gemini agents can ignore this section.

### Agent Coordination Strategy

This project uses two complementary coordination modes: subagents for focused delegation and agent teams for collaborative parallel work. Both should leverage pctx code mode when batching MCP operations.

#### Subagents vs Agent Teams

Use subagents for contained, one-directional tasks. Use agent teams for parallel exploration or cross-discipline coordination. Choose subagents over teams for routine work. See `.memories/subagent-cost-heuristics.md` for model selection (haiku/sonnet/opus), delegation thresholds, and behavioral guardrails. See `.memories/coordination-rules.md` for team operations (lead role, branch discipline, worktree isolation, post-merge cleanup). See `.memories/dispatch-examples.md` for code examples.

#### Agent Definitions

Reusable agent personas live in `.claude/agents/`. Each defines a role, model default, and operating instructions. See `.memories/dreamer-role.md` for detailed dreamer dispatch patterns.

| Agent         | Model                            | Purpose                                                                                            |
| ------------- | -------------------------------- | -------------------------------------------------------------------------------------------------- |
| `dreamer`     | sonnet, opus, or gemini-pro      | Project state guardian. Maintains `.dreams/` and `.memories/`. Never writes source code.           |
| `reviewer`    | sonnet, haiku, or mistral-small  | Code review agent. Reads code and produces structured assessments. Never modifies code.            |
| `implementer` | sonnet, opus, or gemma4:26b      | Code execution agent. Writes code in isolated worktrees. Follows Definition of Done.               |
| `planner`     | sonnet, opus, or qwen3-coder:30b | Implementation planning agent. Produces actionable plans with wave assignments. Never writes code. |

#### General Rules

- Clarify wide-scoped prompts before acting. Don't assume scope — confirm it.
- Prefer local models over paid subagents. Use `nix run .#nixos-config -- -m <model> -p "<prompt>"` as the first choice. Reserve paid subagents for tasks where local model output is demonstrably inadequate.
- Evaluate local model output by filesystem changes, not raw output.
- After completing a task that used subagents or agent teams, include a brief Coordination Summary.

#### Local Model Selection & Orchestration

See `.memories/model-dispatch.md` for per-model heuristics, pipeline selection, and known failure modes. See `.memories/local-models.md` for model inventory and benchmark data.

---

## Gemini CLI

This section is for Gemini CLI agents. Claude agents can ignore it.

- All commands via `run_shell_command` through the Nix flake (e.g., `run_shell_command(command: "nix run .#fmt")`).
- Call Claude: `nix run .#claude -- -p "<prompt>" --dangerously-skip-permissions`
- Call local models: `nix run .#nixos-config -- -m <model> -p "<prompt>"`
- Use `codebase_investigator` for initial analysis, `enter_plan_mode` for non-trivial changes, `generalist` sub-agents for focused tasks.
- Use `save_memory` with scope `project` for persistent context.
- The `dreamer` persona maintains `.dreams/` and `.memories/` — never writes source code. See `.memories/dreamer-role.md`.
