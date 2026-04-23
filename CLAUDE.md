# CLAUDE.md

Notes for Claude Code working in this repo.

## This repo has multiple async contributors

This nixos-config is used across multiple machines (luna + a darwin fleet) and
multiple git/jj identities (`olive.casazza@gmail.com` and
`olive.casazza@schrodinger.com`). Work happens in parallel on different hosts
and gets reconciled later, so **assume the working tree you land in is only one
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
  consolidation).
- VCS: both `git` and `jj` are in use. `jj` is the day-to-day driver, `git`
  remotes are the sync layer.
- Deploy target for observability / LLM services: `luna` (nixos,
  `systems/x86_64-linux/luna`).
- Secrets: sops-nix, decrypted via host keys — don't commit plaintext.

## Cross-repo push targets

The fleet pulls private flake inputs over a `git-daemon` running on luna —
not GitHub. Pushing to a public origin instead of luna will leave nh switch
unable to fetch your changes on every other host.

- `~/Repositories/schrodinger/opencode` → **always push to the `luna` remote**
  (`casazza@luna.local:/srv/git/opencode.git`), not `origin`
  (anomalyco/opencode on GitHub). The fork's `dev` branch is the integration
  line; there is no `main` on luna. nixos-config consumes
  `git+ssh://casazza@luna.local/srv/git/opencode.git?ref=dev`, so anything
  you don't push to luna is invisible to every other Mac on the next nh
  switch. Husky's pre-push hook needs `bun` on PATH; `HUSKY=0` to skip when
  iterating.
- `~/Repositories/schrodinger/hermes-agent` → same pattern (luna mirror at
  `casazza@luna.local:/srv/git/hermes-agent.git`, branch `schrodinger`).
- `~/.config/nixos-config` → push to GitHub `origin/main`. This repo
  isn't proxied through luna; siblings pull directly from GitHub.

## Conflict resolution: merge, don't rebase

- For ANY conflict against published refs (origin/main on nixos-config,
  luna/dev on opencode/hermes), resolve via a **merge commit**, not a
  rebase. Other hosts and other agents may have already fetched those
  commits; rewriting them strands their views.
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
