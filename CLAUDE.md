# CLAUDE.md

Notes for Claude Code working in this repo.

## This repo has multiple async contributors

This nixos-config is the **darwin fleet** config (Macs only). The NixOS
hosts — `desk-nxst-001` and friends — moved to
`~/Repositories/schrodinger/nixstation` in the 2026-04-24 split. Work
happens in parallel across multiple Macs and multiple git/jj identities
(`olive.casazza@gmail.com` and `olive.casazza@schrodinger.com`), and gets
reconciled later, so **assume the working tree you land in is only one
of several live views**.

Before acting:

- Run `git fetch origin` and compare `HEAD` to `origin/main` — `HEAD` may be
  detached (jj default) or behind a sibling machine's recently-pushed work.
- Check `jj log -r 'all()'` as well as `git log --all` — commits can live in
  `refs/jj/keep/...` without being on any git branch. A file you think is
  "missing" may just be on a commit that hasn't been pushed from another host.
- Look for sibling trees like `~/nixos-config*` or
  `~/nixos-config.old.<timestamp>` before assuming something was deleted —
  past consolidation commits have moved the canonical tree between paths.
- Prefer NEW commits over amending / rebasing published history. Other hosts
  may be tracking those refs.

## Workflow specifics

- Primary tree: `~/.config/nixos-config` (canonical after the 2026-04-21
  consolidation; darwin-only after the 2026-04-24 nixstation split).
- VCS: both `git` and `jj` are in use. `jj` is the day-to-day driver, `git`
  remotes are the sync layer.
- NixOS hosts (desk-nxst-001/002/003/004) live in
  `~/Repositories/schrodinger/nixstation`. Anything LiteLLM /
  Open WebUI / ingest / vLLM / observability lives there now, not here.
- Secrets: sops-nix, decrypted via host keys — don't commit plaintext.

## Cross-repo push targets

The fleet pulls private flake inputs over bare git mirrors on
desk-nxst-001 (`/srv/git/<repo>.git`, reached via `git+ssh`) — not
GitHub. Pushing to a public origin instead of the desk-nxst-001 mirror
will leave `nh switch` unable to fetch your changes on every other host.

- `~/Repositories/schrodinger/opencode` → **always push to the
  desk-nxst-001 mirror**
  (`casazza@desk-nxst-001:/srv/git/opencode.git`), not `origin`
  (anomalyco/opencode on GitHub). The fork's `dev` branch is the
  integration line; there is no `main` on the mirror. nixos-config and
  nixstation consume
  `git+ssh://casazza@desk-nxst-001/srv/git/opencode.git?ref=dev`, so
  anything you don't push to the mirror is invisible to every other
  Mac on the next nh switch. Husky's pre-push hook needs `bun` on
  PATH; `HUSKY=0` to skip when iterating.
- `~/Repositories/schrodinger/hermes-agent` → same pattern
  (`casazza@desk-nxst-001:/srv/git/hermes-agent.git`, branch
  `schrodinger`).
- `~/.config/nixos-config` → push to GitHub `origin/main`. This repo
  isn't proxied through the mirror; siblings pull directly from GitHub.
- `~/Repositories/schrodinger/nixstation` → push to GitHub
  `origin/main` (`schrodinger/nixstation`). desk-nxst-001 fetches from
  there for `nh os switch`.

## Conflict resolution: merge, don't rebase

- For ANY conflict against published refs (origin/main on nixos-config
  or nixstation, desk-nxst-001 mirror dev/schrodinger on
  opencode/hermes), resolve via a **merge commit**, not a rebase. Other
  hosts and other agents may have already fetched those commits;
  rewriting them strands their views.
- Never `git push --force` or `--force-with-lease` to published branches.
- Avoid `git commit --amend` once a commit is pushed — make a follow-up
  commit instead.
- If you need to merge and there are conflicts, take the time to actually
  resolve them by reading both sides — don't `git checkout --theirs/--ours`
  blanket-style on a file you don't fully understand.

## Before reporting something as "missing"

Grep the repo, check `jj log -r 'all()'`, and check sibling trees. The most
common "drift" symptom is a jj working copy on a different machine holding
changes that haven't been pushed, not actual lost work.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->

## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
