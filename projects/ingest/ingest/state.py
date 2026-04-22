"""Persistent state — `/var/lib/ingest/state.json`.

Tracks three things:

    1. knowledges: name → knowledge_id      (set once per knowledge)
    2. external_ids: external_id → file_id  (so re-ingest = delete + re-add)
    3. cursors: per-source last-sync marker (JQL/CQL timestamp, github
       issue `since`, obsidian commit sha / tree etag, etc.)

External IDs are the load-bearing idempotency key. Examples:
    jira:OPS-123
    confluence:IT:918273
    github:ocasazza/nixos-config#42
    github-pr:ocasazza/nixos-config#44
    github-doc:ocasazza/nixos-config/docs/foo.md
    obsidian:vault/30-Knowledge-Base/IT-Ops/foo.md

The Open WebUI sink reads the external_id → file_id mapping before
each push; on hit, it DELETEs the old file and creates a fresh one.
This is the pragmatic "idempotent upsert" shape the Files API gives
us — Open WebUI has no by-external-id endpoint.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)


STATE_FILENAME = "state.json"


class IngestState:
    """Thin JSON-file-backed state. Not thread-safe — each oneshot run
    owns the file end-to-end; no concurrent writers by design."""

    def __init__(self, state_dir: Path) -> None:
        self.state_dir = Path(state_dir)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self._path = self.state_dir / STATE_FILENAME
        self._data: dict[str, Any] = self._load()

    # ── io ───────────────────────────────────────────────────────────
    def _load(self) -> dict[str, Any]:
        if not self._path.exists():
            return _empty_state()
        try:
            raw = json.loads(self._path.read_text())
        except Exception as exc:  # noqa: BLE001
            log.warning("state file %s unreadable (%s) — starting fresh", self._path, exc)
            return _empty_state()
        # Migrate older shape (pre-0.2 had only {"knowledges": {}}).
        for k, default in _empty_state().items():
            raw.setdefault(k, default)
        return raw

    def save(self) -> None:
        # Atomic write so an interrupted run doesn't corrupt state.
        tmp_fd, tmp_name = tempfile.mkstemp(dir=self.state_dir, prefix=".state-", suffix=".json")
        try:
            with os.fdopen(tmp_fd, "w") as f:
                json.dump(self._data, f, indent=2, sort_keys=True)
            os.replace(tmp_name, self._path)
        except Exception:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass
            raise

    # ── knowledges ───────────────────────────────────────────────────
    def get_knowledge_id(self, name: str) -> str | None:
        return self._data["knowledges"].get(name)

    def set_knowledge_id(self, name: str, kb_id: str) -> None:
        self._data["knowledges"][name] = kb_id

    # ── external_id ↔ file_id ────────────────────────────────────────
    def get_file_id(self, external_id: str) -> str | None:
        return self._data["external_ids"].get(external_id)

    def set_file_id(self, external_id: str, file_id: str) -> None:
        self._data["external_ids"][external_id] = file_id

    def forget_file_id(self, external_id: str) -> None:
        self._data["external_ids"].pop(external_id, None)

    # ── cursors ──────────────────────────────────────────────────────
    def get_cursor(self, source: str, key: str, default: Any = None) -> Any:
        return self._data["cursors"].get(source, {}).get(key, default)

    def set_cursor(self, source: str, key: str, value: Any) -> None:
        self._data["cursors"].setdefault(source, {})[key] = value

    # ── inspection ───────────────────────────────────────────────────
    @property
    def path(self) -> Path:
        return self._path

    def raw(self) -> dict[str, Any]:
        return self._data


def _empty_state() -> dict[str, Any]:
    return {
        "knowledges": {},
        "external_ids": {},
        "cursors": {},
    }
