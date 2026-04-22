# ingest

Declarative ingestion pipeline for personal/IT knowledge. Three
pull-over-API source adapters feed one sink (Open WebUI Knowledge API)
through LangGraph graphs. Managed at runtime by the NixOS module at
`~/.config/nixos-config/modules/nixos/ingest/`.

No local filesystem dependencies — nothing needs the vault to be
checked out on this host.

## Sources

| Source    | What                                               | Knowledge targets                                      |
|-----------|----------------------------------------------------|--------------------------------------------------------|
| obsidian  | Vault markdown via GitHub Contents API (`ocasazza/obsidian`) | `kb-notes-personal`, `kb-it-docs`, `kb-systems-internal`, `kb-systems-external` |
| atlassian | Jira issues + Confluence pages (Atlassian Cloud)   | `kb-it-tickets`, `kb-it-docs`                           |
| github    | Issues, PRs, and repo docs for a configured list   | `kb-it-tickets`, `kb-systems-internal`, `kb-systems-external` |

All incremental: `obsidian` diffs by blob sha against a cached tree,
`atlassian` uses JQL/CQL `updated`/`lastModified` cursors, `github`
uses `since=` for issues and blob-sha diffing for docs.

## Sink

`ingest/sinks/openwebui.py` speaks four Open WebUI endpoints (verified
against `/openapi.json` on 2026-04-21):

- `POST /api/v1/knowledge/create`        — one-time knowledge creation
- `GET  /api/v1/knowledge/`              — list (to discover existing ids)
- `POST /api/v1/files/`                  — multipart upload, returns file_id
- `DELETE /api/v1/files/{id}`            — used for idempotent replace
- `POST /api/v1/knowledge/{id}/file/add` — body `{file_id}`

Idempotency is keyed by `external_id` (e.g. `jira:OPS-123`,
`github:ocasazza/nixos-config#42`, `obsidian:vault/30-Knowledge-Base/IT-Ops/foo.md`).
On re-ingest, the sink deletes the old Open WebUI file and re-uploads
the fresh content. Knowledge IDs + external_id→file_id mappings are
cached in `/var/lib/ingest/state.json`.

## Dev

```sh
cd ~/.config/nixos-config/projects/ingest
nix develop ../..
uv sync
uv run ingest --help
uv run langgraph dev          # visual graph editor at :2024
```

## Graphs

- `obsidian`  — `run → END`                          (one pass, returns add/delete counts)
- `atlassian` — `pull_jira → pull_confluence → summarize → END`
- `github`    — `run → END`                          (walks all configured repos)

All three are declared in `langgraph.json` so `langgraph dev` / `langgraph serve`
pick them up.

## Env

All env vars are `INGEST_*`-prefixed (see `ingest/config.py`). The
NixOS module renders them into each systemd unit from Nix options; in
dev you can drop them into `.env` and direnv will load them.
