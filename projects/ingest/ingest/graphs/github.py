"""LangGraph graph — github adapter → Open WebUI.

One node — the adapter is already a single top-level generator that
iterates across every configured repo for issues + PRs + docs.

Edges:
    run → END
"""

from __future__ import annotations

import logging
from typing import Any, TypedDict

from langgraph.graph import END, StateGraph

from ingest.adapters import github as github_adapter
from ingest.config import get_settings
from ingest.sinks.openwebui import OpenWebUIClient
from ingest.state import IngestState

log = logging.getLogger(__name__)


class GithubGraphState(TypedDict, total=False):
    pushed: int
    errors: list[str]


def _run_node(state: GithubGraphState) -> GithubGraphState:
    settings = get_settings()
    st = IngestState(settings.state_dir)
    pushed = 0
    errors: list[str] = []

    with OpenWebUIClient(settings=settings, state=st) as client:
        for doc in github_adapter.iter_docs(settings=settings, state=st):
            try:
                client.push(
                    knowledge_name=doc.knowledge_name,
                    external_id=doc.external_id,
                    filename=doc.filename,
                    content=doc.content,
                    metadata=doc.metadata,
                )
                pushed += 1
            except Exception as exc:  # noqa: BLE001
                log.exception("github push failed for %s", doc.external_id)
                errors.append(f"{doc.external_id}: {exc}")

    log.info("github run: pushed=%d errors=%d", pushed, len(errors))
    return {"pushed": pushed, "errors": errors}


def build_graph() -> Any:
    sg = StateGraph(GithubGraphState)
    sg.add_node("run", _run_node)
    sg.set_entry_point("run")
    sg.add_edge("run", END)
    return sg.compile()


graph = build_graph()
