# Skill Registry

Read this file first. Full `SKILL.md` contents load only when a skill's
triggers match the current task. Machine-readable equivalent:
`skills/_manifest.jsonl`.

## skillforge

Creates new skills from observed patterns and recurring tasks.
Triggers: "create skill", "new skill", "I keep doing this manually"

## memory-manager

Reads, scores, and consolidates memory. Runs reflection cycles.
Triggers: "reflect", "what did I learn", "compress memory"

## git-proxy

All git operations with safety constraints.
Triggers: "commit", "push", "branch", "merge", "rebase"
Constraints: never force push to main; run tests before push.

## debug-investigator

Systematic debugging: reproduce, isolate, hypothesize, verify.
Triggers: "debug", "why is this failing", "investigate"

## deploy-checklist

Pre-deployment verification against a structured checklist.
Triggers: "deploy", "ship", "release", "go live"
Constraints: all tests passing, no unresolved TODOs in diff,
requires human approval for production.

## data-layer

Cross-harness activity monitoring and dashboard exports. Use it as the
injected dashboard surface when users ask naturally.
Triggers: "data layer", "dashboard", "show me the dashboard",
"what did my agents do", "agent analytics", "agent status", "resource usage",
"usage report", "cron monitoring", "daily report", "tokens",
"terminal dashboard", "TUI"
Constraints: local-only by default; no screenshot delivery without explicit user
approval; do not commit private `.agent/data-layer/` exports.

## data-flywheel

Turns approved, redacted runs into reusable local artifacts: trace records,
context cards, eval cases, training-ready JSONL, and flywheel metrics.
Triggers: "data flywheel", "trace to train", "training traces",
"context cards", "eval cases", "approved runs", "vertical intelligence"
Constraints: local-only by default; human-approved runs only; redaction required
before trainable; does not train models.

## design-md

Uses a root `DESIGN.md` as the portable visual system contract for
Google Stitch workflows. Loads only when `DESIGN.md` exists at the
project root.
Triggers: "DESIGN.md", "design.md", "Google Stitch", "design tokens",
"design system", "visual design"
Preconditions: DESIGN.md exists at project root.
Constraints: prefer DESIGN.md tokens over invented values, do not modify
DESIGN.md unless the user explicitly asks, preserve unknown sections when
an edit IS authorised, validate with `npx @google/design.md lint DESIGN.md`
when available.

## tldraw

Draw, diagram, sketch, or lay out ideas on a live tldraw canvas.
Worthwhile drawings snapshot into this skill's local store
(`skills/tldraw/store.py`) for recall across sessions.
Triggers: "draw", "diagram", "sketch", "wireframe", "flowchart",
"mind-map", "visualize", "whiteboard"
Constraints: get_canvas before edits; max 200 shapes per create_shape call.
Requires: tldraw MCP server wired in the harness's MCP config; user has
http://localhost:3030 open. Opt-in via `.features.json` (`tldraw: true`).

## snowfall-lib

Project-specific skill for the snowfall-lib Nix flake layout used by
nixos-config. Loads when adding/moving packages, modules, overlays, systems,
homes, shells, checks, templates, or libraries; configuring `mkFlake`
(namespace, channels-config, alias, external modules); migrating between
v1→v2 or v2→v3; or debugging "where does this file go / why isn't it picked up".
Triggers: "snowfall", "mkFlake", "add module", "add package", "add system",
"add home", "add overlay", "add shell", "add check", "add template", "add library"
Preconditions: flake.nix uses snowfall-lib input.
Constraints: preserve existing `snowfall.namespace`; files must be `default.nix`;
new files must be `git add`-ed before `nix flake show` will see them.
