"""Typer CLI for ingestion runs.

    ingest run-once obsidian          # one obsidian pull (timer target)
    ingest run-once atlassian         # one Atlassian pull (timer target)
    ingest run-once github            # one GitHub pull (timer target)
    ingest debug config               # dump resolved settings as JSON
    ingest debug state                # dump state.json contents

Each `run-once` subcommand invokes the matching LangGraph graph, so a
manual invocation reproduces EXACTLY what the systemd timer runs.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import typer
from rich.console import Console
from rich.logging import RichHandler

from ingest.config import get_settings
from ingest.graphs.atlassian import graph as atlassian_graph
from ingest.graphs.github import graph as github_graph
from ingest.graphs.obsidian import graph as obsidian_graph
from ingest.state import IngestState
from ingest.telemetry import init_tracing

console = Console()
app = typer.Typer(add_completion=False, help="Declarative ingestion pipeline.")
run_once = typer.Typer(help="One-shot runs — used by systemd timers.")
debug = typer.Typer(help="Development utilities.")
app.add_typer(run_once, name="run-once")
app.add_typer(debug, name="debug")


def _setup_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler(rich_tracebacks=True, console=console)],
    )


@app.callback()
def _root(verbose: bool = typer.Option(False, "--verbose", "-v")) -> None:
    _setup_logging(verbose)
    init_tracing()


@run_once.command("obsidian")
def run_once_obsidian() -> None:
    """Pull vault markdown from the obsidian GitHub repo."""
    result = obsidian_graph.invoke({})
    console.print_json(data=_jsonable(result))


@run_once.command("atlassian")
def run_once_atlassian() -> None:
    """Pull updated Jira issues + Confluence pages, push to Open WebUI."""
    result = atlassian_graph.invoke({})
    console.print_json(data=_jsonable(result))


@run_once.command("github")
def run_once_github() -> None:
    """Pull issues / PRs / docs for each configured repo, push to Open WebUI."""
    result = github_graph.invoke({})
    console.print_json(data=_jsonable(result))


@debug.command("config")
def debug_config() -> None:
    """Print the resolved settings (minus secrets)."""
    s = get_settings()
    redacted = {}
    for k, v in s.model_dump().items():
        if k in {"openwebui_token", "atlassian_api_token", "github_token", "obsidian_token"}:
            redacted[k] = "***" if v else ""
        elif isinstance(v, Path):
            redacted[k] = str(v)
        else:
            redacted[k] = v
    console.print_json(data=_jsonable(redacted))


@debug.command("state")
def debug_state() -> None:
    """Dump /var/lib/ingest/state.json."""
    st = IngestState(get_settings().state_dir)
    console.print_json(data=_jsonable(st.raw()))


def _jsonable(obj: Any) -> Any:
    try:
        json.dumps(obj)
        return obj
    except TypeError:
        if isinstance(obj, dict):
            return {k: _jsonable(v) for k, v in obj.items()}
        if isinstance(obj, (list, tuple)):
            return [_jsonable(i) for i in obj]
        return str(obj)


if __name__ == "__main__":
    app()
