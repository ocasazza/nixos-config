# AGENTS.md

This project uses **nason-skills** as a centralized source of agent skills,
distributed to AI clients (gemini, claude, hermes, pi) via nixos-config.
Project-specific rules live in `.agent/protocols/nixos-config.md`.

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## Session start — read in this order

1. `.agent/protocols/nixos-config.md` — project-specific protocol (Nix command rules, snowfall-lib usage, Definition of Done)
2. `.agent/memory/personal/PREFERENCES.md` — user conventions

## Skills

Skills are centralized in the `nason-skills` flake input and distributed
to each AI client by nixos-config modules. Skills include network testing,
LibreNMS monitoring, snowfall-lib, litellm management, and more.

## Project-specific rules

This repo has its own conventions covering Nix flake usage, snowfall-lib
layout, the `.dreams/` / `.memories/` directories, Definition of Done,
agent coordination, and per-harness sections (Claude Code, Gemini CLI).
Read `.agent/protocols/nixos-config.md` in full before any non-trivial task.

## Hard rules

- No force push to `main`, `production`, or `staging`.
- All shell commands go through the Nix flake (`nix run .#<app>` or
  `nix develop --command <cmd>`). Never rely on globally installed
  binaries. See `.agent/protocols/nixos-config.md` § Command Execution
  Rules for the full discipline.

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
