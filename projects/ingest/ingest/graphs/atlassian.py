"""LangGraph graph — Atlassian adapter → Open WebUI.

Edges:
    pull_jira → pull_confluence → summarize → END

Each pull_* node streams AtlassianDocs from the adapter straight into
the sink's idempotent push() so we don't materialize the list in memory.
"""

from __future__ import annotations

import logging
from typing import Any, TypedDict

from langgraph.graph import END, StateGraph

from ingest.adapters import atlassian as atlassian_adapter
from ingest.config import get_settings
from ingest.sinks.openwebui import OpenWebUIClient
from ingest.state import IngestState

log = logging.getLogger(__name__)


class AtlassianGraphState(TypedDict, total=False):
    jira_pushed: int
    confluence_pushed: int
    errors: list[str]


def _push_stream(stream: Any, client: OpenWebUIClient) -> tuple[int, list[str]]:
    pushed = 0
    errors: list[str] = []
    for doc in stream:
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
            log.exception("atlassian push failed for %s", doc.external_id)
            errors.append(f"{doc.external_id}: {exc}")
    return pushed, errors


def _pull_jira_node(state: AtlassianGraphState) -> AtlassianGraphState:
    settings = get_settings()
    st = IngestState(settings.state_dir)
    with OpenWebUIClient(settings=settings, state=st) as client:
        try:
            pushed, errors = _push_stream(
                atlassian_adapter.pull_jira(settings=settings, state=st),
                client,
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("jira pull failed")
            pushed, errors = 0, [f"jira: {exc}"]
    return {
        **state,
        "jira_pushed": pushed,
        "errors": (state.get("errors") or []) + errors,
    }


def _pull_confluence_node(state: AtlassianGraphState) -> AtlassianGraphState:
    settings = get_settings()
    st = IngestState(settings.state_dir)
    with OpenWebUIClient(settings=settings, state=st) as client:
        try:
            pushed, errors = _push_stream(
                atlassian_adapter.pull_confluence(settings=settings, state=st),
                client,
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("confluence pull failed")
            pushed, errors = 0, [f"confluence: {exc}"]
    return {
        **state,
        "confluence_pushed": pushed,
        "errors": (state.get("errors") or []) + errors,
    }


def _summarize_node(state: AtlassianGraphState) -> AtlassianGraphState:
    log.info(
        "atlassian run: jira=%d confluence=%d errors=%d",
        state.get("jira_pushed") or 0,
        state.get("confluence_pushed") or 0,
        len(state.get("errors") or []),
    )
    return state


def build_graph() -> Any:
    sg = StateGraph(AtlassianGraphState)
    sg.add_node("pull_jira", _pull_jira_node)
    sg.add_node("pull_confluence", _pull_confluence_node)
    sg.add_node("summarize", _summarize_node)
    sg.set_entry_point("pull_jira")
    sg.add_edge("pull_jira", "pull_confluence")
    sg.add_edge("pull_confluence", "summarize")
    sg.add_edge("summarize", END)
    return sg.compile()


graph = build_graph()
