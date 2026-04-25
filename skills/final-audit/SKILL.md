---
name: final-audit
description: Run a cross-cutting audit across all code produced for a feature. Use when a feature is complete, all PRs are merged, and the user wants a final review for security issues, logic errors, consistency, and best practices.
---

# Final Audit

Review all code produced for a feature as a whole, looking for issues
that are only visible across the full implementation — not within a
single PR.

This audit is not a substitute for per-PR code review. It looks for
different things: patterns that were introduced early and replicated
incorrectly, inconsistencies between modules, and systemic issues that
no single PR reviewer could have caught.

## Context

Before starting, read the active rig's `AGENTS.md` and `CLAUDE.md` to
ground the audit in project conventions. If the rig keeps `.memories/`
and `.dreams/`, read the relevant ones to understand the feature's
planning history, design decisions, and any deliberation outcomes.

## Process

### 1. Locate the feature

Ask the user for the parent PRD (typically in the rig's `docs/` or
equivalent). Read it in full, including all child issues and task
files, along with their acceptance criteria.

### 2. Identify the scope

From the PRD and its issues, build a list of every file that was
created or modified as part of this feature. Ask the user to confirm
the list is complete.

### 3. Explore the implementation

Read all files in scope. For each module, understand:

- What it is responsible for
- What its public interface is
- How it interacts with other modules in scope
- How it interacts with the rest of the codebase outside the feature
- Whether it follows the conventions in `AGENTS.md` / `CLAUDE.md`

Do not audit yet. Build a complete mental model first.

### 4. Audit for systemic issues

Check the following categories. For each finding, note the category,
the location, a description of the problem, and a suggested fix.

**Consistency**

- Do all modules follow the same naming conventions as each other and
  as the surrounding codebase?
- Are error types, error messages, and error handling patterns
  consistent across modules?
- Are similar operations implemented the same way everywhere?
- Are internal API contracts consistent — do callers and
  implementations agree on types, nullability, and failure modes?
- Are toolchain patterns consistent (build helpers, derivation
  structure, check definitions)?

**Security**

- Is user input validated and sanitised at every entry point?
- Are authentication and authorisation checks applied consistently —
  not just at one adapter but at all of them?
- Is sensitive data (API keys, tokens, PII) handled consistently and
  never logged or exposed?
- Are there injection risks at any layer?
- Are external fetches using verified hashes / signatures?
- Are secrets accessed only through the project's secret store?

**Logic**

- Are there race conditions or ordering assumptions that could fail
  under concurrent use?
- Are all failure modes handled — network errors, partial failures,
  timeouts, malformed responses?
- Are there off-by-one errors, incorrect boundary conditions, or
  incorrect assumptions about data ranges?
- Does the implementation match the acceptance criteria in every
  child issue, including edge cases?

**Best practices**

- Is there duplicated logic that should be extracted into a shared
  module?
- Are there deep modules that were implemented as shallow ones —
  complex interfaces hiding little functionality?
- Are there any modules that have taken on too many responsibilities
  and should be split?
- Are tests testing external behaviour or implementation details? Are
  they brittle?
- Is there dead code introduced by this feature?
- Are all build commands going through the rig's pinned toolchain?

**Alignment with design goals**

- Does the implementation respect the design goals stated in the rig's
  `AGENTS.md` (speed, cost, safety, simplicity, etc.)?

### 5. Prioritise findings

Group findings by severity:

- **Critical**: security vulnerability, data loss risk, or logic error
  that will cause incorrect behaviour in production
- **High**: inconsistency or logic error that will cause problems
  under realistic conditions
- **Medium**: best practice violation or inconsistency that will
  cause maintenance problems
- **Low**: minor inconsistency or style issue with no functional
  impact

### 6. Present the report

Present findings grouped by severity. For each finding:

- **Location**: file and line range
- **Category**: which audit category it falls under
- **Problem**: what is wrong and why it matters
- **Suggestion**: what to do about it

After presenting all findings, give an overall assessment: is this
feature safe to leave in production as-is, or are there critical or
high findings that should be resolved before considering the feature
done?

Ask the user which findings they want to act on and in what order.
Do not make any changes without explicit approval.

### 7. Save the report

Save the audit report to the rig's docs directory (e.g.
`docs/audit-<feature>.md`). Confirm filename with the user.

If the rig keeps `.memories/`, update it with a state file recording
the audit outcome.

<audit-report-template>
# Audit Report: <feature-name>

Parent PRD: `<prd-filename>`
Date: <date>
Files in scope: <count>

## Summary

<2-3 sentence overall assessment. Is this safe to leave in production?
What is the most important thing to fix?>

## Critical findings

### <n>. <Short title>

**Location**: `<file>:<line-range>`
**Category**: <Security / Logic / Consistency / Best practices / Design goals>
**Problem**: <What is wrong and why it matters>
**Suggestion**: <What to do about it>

---

## High findings

(same structure)

## Medium findings

(same structure)

## Low findings

(same structure)

## No findings

<List any audit categories where no issues were found.>
</audit-report-template>
