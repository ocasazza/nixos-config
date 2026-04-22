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

## Before reporting something as "missing"

Grep the repo, check `jj log -r 'all()'`, and check sibling trees. The most
common "drift" symptom is a jj working copy on a different machine holding
changes that haven't been pushed, not actual lost work.
