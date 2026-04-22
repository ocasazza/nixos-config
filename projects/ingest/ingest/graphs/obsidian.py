"""LangGraph graph — obsidian adapter → Open WebUI.

Edges:
    list_changed → push_each → commit_cursors → END

`list_changed` pulls the head commit sha + tree, diffs against prior
run's cursor, yields (add | delete) events.
`push_each` runs the sink's idempotent upsert for adds, delete-by-
external-id for deletes.
`commit_cursors` atomically writes the new head sha + per-path blob
shas so the next run is truly incremental.
"""

from __future__ import annotations

import logging
from typing import Any, TypedDict

from langgraph.graph import END, StateGraph

from ingest.adapters.obsidian import (
    collect_current_tree,
    iter_changed_docs,
    update_cursors_after_run,
)
from ingest.config import get_settings
from ingest.sinks.openwebui import OpenWebUIClient
from ingest.state import IngestState

log = logging.getLogger(__name__)


class ObsidianState(TypedDict, total=False):
    adds: int
    deletes: int
    errors: list[str]
    head_sha: str | None


def _run_node(state: ObsidianState) -> ObsidianState:
    settings = get_settings()
    st = IngestState(settings.state_dir)

    adds = 0
    deletes = 0
    errors: list[str] = []

    with OpenWebUIClient(settings=settings, state=st) as client:
        for event, doc, vault_path in iter_changed_docs(settings=settings, state=st):
            try:
                if event == "add" and doc is not None:
                    client.push(
                        knowledge_name=doc.knowledge_name,
                        external_id=doc.external_id,
                        filename=doc.filename,
                        content=doc.content,
                        metadata=doc.metadata,
                    )
                    adds += 1
                elif event == "delete" and vault_path is not None:
                    ext_id = f"obsidian:{vault_path}"
                    prior = st.get_file_id(ext_id)
                    if prior:
                        client.delete_file(prior)
                        st.forget_file_id(ext_id)
                        st.save()
                        deletes += 1
            except Exception as exc:  # noqa: BLE001
                log.exception("obsidian push failed")
                errors.append(str(exc))

    # Advance cursors only after a successful pass (adds/deletes may be
    # 0, that's fine — we still want to record head sha so the next run
    # short-circuits).
    head_sha, blob_shas = collect_current_tree(settings=settings)
    update_cursors_after_run(head_sha=head_sha, blob_shas=blob_shas, state=st)

    log.info("obsidian run: %d adds, %d deletes, %d errors", adds, deletes, len(errors))
    return {"adds": adds, "deletes": deletes, "errors": errors, "head_sha": head_sha}


def build_graph() -> Any:
    sg = StateGraph(ObsidianState)
    sg.add_node("run", _run_node)
    sg.set_entry_point("run")
    sg.add_edge("run", END)
    return sg.compile()


graph = build_graph()
