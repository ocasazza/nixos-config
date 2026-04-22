"""Typer CLI: `swarm run "..."` dispatches through the LangGraph swarm."""

from __future__ import annotations

import json

import typer
from rich.console import Console
from rich.panel import Panel

from . import config as cfg_mod
from . import telemetry
from .graph import run_sync
from .research import run_sync as research_run_sync

app = typer.Typer(no_args_is_help=True, add_completion=False)
console = Console()


@app.command()
def run(
    task: str = typer.Argument(..., help="The task the swarm should solve."),
    trace: bool = typer.Option(True, help="Send spans to Phoenix."),
) -> None:
    """Run the swarm once on `task` and print the synthesized answer."""
    cfg = cfg_mod.load()
    if trace:
        telemetry.init(cfg.phoenix_endpoint)

    try:
        result = run_sync(task, cfg)
    finally:
        if trace:
            telemetry.shutdown()

    plan = result.get("plan") or []
    console.print(Panel(f"[bold]Plan[/bold]: {len(plan)} subtasks"))
    for sub in plan:
        console.print(f"  [{sub.get('kind')}] {sub.get('id')}: {sub.get('instruction')}")

    console.print(Panel(result.get("answer", "(no answer)"), title="Answer"))

    if trace:
        console.print(f"\n[dim]Phoenix UI: {cfg.phoenix_endpoint.replace('/v1/traces', '')}[/dim]")


@app.command()
def research(
    question: str = typer.Argument(..., help="The research question."),
    trace: bool = typer.Option(True, help="Send spans to Phoenix."),
) -> None:
    """Run the 8-stage research pipeline on `question`."""
    cfg = cfg_mod.load()
    if trace:
        telemetry.init(cfg.phoenix_endpoint, service_name="swarm-research")

    try:
        result = research_run_sync(question, cfg)
    finally:
        if trace:
            telemetry.shutdown()

    claims = result.get("claims") or []
    console.print(Panel(f"[bold]Claims[/bold]: {len(claims)}"))
    for c in claims:
        console.print(f"  [{c.get('source')}] {c.get('id')}: {c.get('question')}")

    if result.get("critique"):
        console.print(Panel(result["critique"], title="Critique"))

    console.print(Panel(result.get("answer", "(no answer)"), title="Answer"))

    if trace:
        console.print(
            f"\n[dim]Phoenix UI: {cfg.phoenix_endpoint.replace('/v1/traces', '')}[/dim]"
        )


@app.command(name="config")
def show_config() -> None:
    """Dump the effective runtime config."""
    console.print_json(json.dumps(cfg_mod.load().__dict__, default=str))


if __name__ == "__main__":
    app()
