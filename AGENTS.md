# AGENTS.md

This project uses the **[agentic-stack](https://github.com/codejunkie99/agentic-stack)**
portable brain. Memory, skills, and protocols live in `.agent/`. Project-
specific rules live in `.agent/protocols/nixos-config.md`.

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## Session start — read in this order

1. `.agent/AGENTS.md` — the map of the brain (memory layers, review queue, skills, tools)
2. `.agent/memory/personal/PREFERENCES.md` — user conventions
3. `.agent/memory/working/REVIEW_QUEUE.md` — pending lessons awaiting review
4. `.agent/memory/semantic/LESSONS.md` — distilled lessons
5. `.agent/protocols/permissions.md` — hard rules (read before any tool call)
6. `.agent/protocols/nixos-config.md` — project-specific protocol (Nix command rules, snowfall-lib usage, dreams/memories workflow, Definition of Done)

## Recall before non-trivial tasks

For any task involving **deploy**, **ship**, **release**, **migration**,
**schema change**, **timestamp** / **timezone** / **date**, **failing test**,
**debug**, **investigate**, or **refactor**, run recall FIRST and present
the results before acting:

```sh
nix develop --command agentic-recall "<one-line description of what you're about to do>"
# or, if the bin shim isn't on PATH yet:
python3 .agent/tools/recall.py "<description>"
```

Surface results in a `Consulted lessons before acting:` block. If a
surfaced lesson would be violated by your intended action, stop and
explain why.

## Skills

- Read `.agent/skills/_index.md` first for discovery.
- Load a full `SKILL.md` only when its triggers match the current task.
- Project-specific skills (e.g., `snowfall-lib`) live alongside upstream
  agentic-stack seed skills in `.agent/skills/`.

## Memory

- Update `.agent/memory/working/WORKSPACE.md` as you work.
- After significant actions, run
  `python3 .agent/tools/memory_reflect.py <skill> <action> <outcome> --note "<why>"`.
- Never delete memory entries; archive only.
- Quick state: `python3 .agent/tools/show.py` (or `agentic-show`).
- Teach a rule in one shot:
  `python3 .agent/tools/learn.py "<rule>" --rationale "<why>"`
  (or `agentic-learn`).

## Project-specific rules

Beyond the agentic-stack workflow above, this repo has its own conventions
covering Nix flake usage, snowfall-lib layout, the `.dreams/` /
`.memories/` directories (separate from `.agent/memory/`), Definition of
Done, agent coordination, and per-harness sections (Claude Code,
Gemini CLI). Read `.agent/protocols/nixos-config.md` in full before any
non-trivial task.

## Hard rules

- No force push to `main`, `production`, or `staging`.
- No modification of `.agent/protocols/permissions.md`.
- Never hand-edit `.agent/memory/semantic/LESSONS.md` — use `graduate.py`.
- If `REVIEW_QUEUE.md` shows pending > 10 or oldest > 7 days, review
  candidates before starting substantive work.
- All shell commands go through the Nix flake (`nix run .#<app>` or
  `nix develop --command <cmd>`). Never rely on globally installed
  binaries. See `.agent/protocols/nixos-config.md` § Command Execution
  Rules for the full discipline.
