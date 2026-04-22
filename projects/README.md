# projects/

Declaratively managed LangGraph Server projects. Each subdirectory is a
self-contained Python project (`pyproject.toml` + `uv.lock` +
`langgraph.json`) that gets served by a dedicated `langgraph-<name>`
systemd unit on whichever host enables it.

Currently declared:

- `swarm/` — LangGraph + LiteLLM + Phoenix multi-agent swarm over
  vLLM/exo. Served at `luna:2024`.
- `ingest/` — Declarative pull-sync from Obsidian vault / Atlassian /
  GitHub into Open WebUI Knowledge. Served at `luna:2025` (loopback).

## Adding a project

1. Drop a new directory under `projects/<name>/` with (at minimum)
   `pyproject.toml`, `uv.lock`, and `langgraph.json`. The shape should
   mirror an existing sibling.
2. Enable it on the relevant host by adding an entry under
   `local.langgraphServer.projects` — e.g. on luna:

   ```nix
   local.langgraphServer.projects.<name> = {
     projectDir = ../../../projects/<name>;
     port = 2026;
     openFirewall = false;
   };
   ```

   The relative path (`../../../projects/<name>`) resolves to a
   `/nix/store/...` path at build time. The systemd unit's venv
   bootstrap runs `uv pip install --editable` against that store path,
   so pyproject / lockfile bumps take effect on the next `nixos-rebuild`.

3. Rebuild the host (`nh os switch`). The module provisions the venv at
   `/var/lib/langgraph/venv/<name>` on first start.

## How `langgraph dev` finds the graph

Each project's `langgraph.json` lists its graph factories under
`graphs.<id>`. That's the canonical source of truth — the service
invokes `langgraph dev --config <project>/langgraph.json` with no extra
knowledge of graph ids.

## Observability

All projects get the same OTLP + Phoenix wiring injected by the
`langgraph-server` module:

- `OTEL_EXPORTER_OTLP_ENDPOINT` / `PHOENIX_COLLECTOR_ENDPOINT`
- `OPENAI_API_BASE` → LiteLLM proxy at :4000
- `OPENAI_API_KEY` → `sk-swarm-local`

Graphs that use `langchain-openai` pick these up automatically.
