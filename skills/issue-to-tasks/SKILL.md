---
name: issue-to-tasks
description: Break an issue into concrete, ordered, AI-executable tasks. Use when the user wants to implement an issue, start work on a ticket, or break down an issue into smaller steps.
---

# Issue to Tasks

Break a single vertical-slice issue into concrete, ordered tasks that
can each be completed in one focused AI session.

## Context

Read the active rig's `AGENTS.md` and `CLAUDE.md` for project
conventions (build commands, formatting rules, layered architecture).
If the rig keeps `.memories/`, read the relevant ones to understand the
current project state before drafting tasks.

Task files are AI-executable instructions. Save them where the rig
prefers (e.g. `.dreams/`, `.tasks/`, `docs/tasks/`). Include an
`AI-ONLY` header so future readers know they're for machine
consumption.

## Process

### 1. Locate the issue

Ask the user for the issue. If not provided, ask for the issue number,
filename, or beads ID.

Read the parent PRD referenced in the issue's "Parent PRD" field.

### 2. Explore the codebase

Explore the parts of the codebase touched by this issue. Run
exploration through the rig's pinned toolchain. Focus on:

- Files and modules that will be created or modified
- Existing patterns to follow (naming conventions, error handling,
  test structure)
- Any interfaces or contracts this issue must respect
- The rig's build/check/test commands

### 3. Draft the task list

Break the issue into ordered tasks. Each task must:

- Be completable in a single AI session (one focused prompt
  exchange)
- Have a clear, verifiable output (a file, a passing test, a working
  endpoint)
- Follow the dependency order the rig's architecture implies

Label each task with its type:

- **WRITE**: create or modify production code
- **TEST**: write or update tests
- **MIGRATE**: schema or data migration
- **CONFIG**: environment, tooling, or build-system changes
- **REVIEW**: human decision required before proceeding

Prefer WRITE and TEST tasks interleaved over a block of WRITE
followed by a block of TEST.

### 4. Quiz the user

Present the proposed task list as a numbered list. For each task show:

- **Title**: short imperative description
- **Type**: WRITE / TEST / MIGRATE / CONFIG / REVIEW
- **Output**: what exists or passes when this task is done
- **Depends on**: task numbers that must complete first

Ask the user:

- Does the order feel right?
- Are any tasks too large to complete in one session?
- Are any tasks so small they should be merged?
- Are all REVIEW tasks correctly identified?

Iterate until the user approves the list.

### 5. Write the task file

Save the approved task list to the rig's task directory. Propose a
filename (e.g. `tasks-issue-<n>.md`). Confirm with the user.

Use the task file template below.

If the rig keeps `.memories/`, update it with a state file recording
the task breakdown.

Do NOT modify the parent issue or the parent PRD.

<task-file-template>
<!-- AI-ONLY: This file is designed for machine consumption. Do not optimize for human readability. -->

# Tasks for Issue <n>: <issue-title>

Parent issue: `<issue-filename>`
Parent PRD: `<prd-filename>`

## Tasks

### <n>. <Task title>

**Type**: WRITE / TEST / MIGRATE / CONFIG / REVIEW
**Output**: <what exists or passes when done>
**Depends on**: <task numbers or "none">

<A short paragraph describing exactly what to do. Written as an
instruction to the AI that will execute it. Include: which files to
touch, which pattern to follow, which existing code to use as
reference. Specify rig-toolchain commands for verification. Do NOT
include code snippets — describe intent, not implementation.>

---

</task-file-template>
