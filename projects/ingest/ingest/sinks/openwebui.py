"""Open WebUI Knowledge sink.

Idempotent push-by-external-id flow:

    if external_id in state:
        DELETE /api/v1/files/{file_id}                # old copy
        (attach auto-removed when the file object is deleted)
    POST   /api/v1/files/            multipart → new file_id
    POST   /api/v1/knowledge/{kb}/file/add   body {file_id}

Knowledge IDs are resolved lazily and cached in /var/lib/ingest/state.json
so we don't pay the list-knowledges round trip on every push.

Endpoints verified against the running Open WebUI's OpenAPI spec at
http://localhost:8080/openapi.json on 2026-04-21:
    POST   /api/v1/knowledge/create   body KnowledgeForm(name, description)
    GET    /api/v1/knowledge/         paginated list
    POST   /api/v1/files/             multipart(file, metadata?)
    DELETE /api/v1/files/{id}         by file id
    POST   /api/v1/knowledge/{id}/file/add     body KnowledgeFileIdForm
    POST   /api/v1/knowledge/{id}/file/remove  body KnowledgeFileIdForm (optional)
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import httpx

from ingest.config import Settings, get_settings
from ingest.state import IngestState

log = logging.getLogger(__name__)


class OpenWebUIClient:
    """Thin, synchronous client over the subset of endpoints we need."""

    def __init__(
        self,
        settings: Settings | None = None,
        state: IngestState | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.state = state or IngestState(self.settings.state_dir)
        self._client = http_client or httpx.Client(
            base_url=self.settings.openwebui_url,
            headers={"Authorization": f"Bearer {self.settings.openwebui_token}"},
            timeout=60.0,
        )
        # Per-instance mirror of state's knowledges — avoids reload chatter.
        self._kb_id_cache: dict[str, str] = {}

    # ── knowledge resolution ─────────────────────────────────────────
    def ensure_knowledge(self, name: str, description: str | None = None) -> str:
        """Return the knowledge id for `name`, creating it if missing.

        Idempotent: results cached in state.json + in-memory so subsequent
        calls avoid the list round trip. Open WebUI allows duplicate names,
        so first-match-wins on the listing.
        """
        if name in self._kb_id_cache:
            return self._kb_id_cache[name]

        cached = self.state.get_knowledge_id(name)
        if cached:
            self._kb_id_cache[name] = cached
            return cached

        kb_id = self._find_knowledge_by_name(name)
        if kb_id is None:
            kb_id = self._create_knowledge(
                name=name,
                description=description or self.settings.resolve_knowledge_description(name),
            )
        self.state.set_knowledge_id(name, kb_id)
        self.state.save()
        self._kb_id_cache[name] = kb_id
        return kb_id

    def _find_knowledge_by_name(self, name: str) -> str | None:
        page = 1
        while True:
            resp = self._client.get("/api/v1/knowledge/", params={"page": page})
            resp.raise_for_status()
            payload = resp.json() or []
            # The bare /knowledge/ endpoint returns a list; newer builds may
            # wrap in {"data": [...]}. Accept both.
            if isinstance(payload, dict):
                items = payload.get("data") or payload.get("knowledge_bases") or []
            else:
                items = payload
            if not items:
                return None
            for item in items:
                if item.get("name") == name:
                    return item["id"]
            if len(items) < 30:  # heuristic: last page
                return None
            page += 1

    def _create_knowledge(self, name: str, description: str) -> str:
        resp = self._client.post(
            "/api/v1/knowledge/create",
            json={"name": name, "description": description},
        )
        resp.raise_for_status()
        body = resp.json()
        if not body or "id" not in body:
            raise RuntimeError(f"create_knowledge returned no id: {body!r}")
        log.info("created knowledge %s → %s", name, body["id"])
        return body["id"]

    # ── file lifecycle ───────────────────────────────────────────────
    def upload_file(
        self,
        *,
        filename: str,
        content: bytes | str,
        metadata: dict[str, Any] | None = None,
    ) -> str:
        """Upload a file to Open WebUI and return its file_id.

        We construct the multipart entirely from in-memory content — no
        temp files on disk, since the adapters already render to memory.
        """
        data_bytes = content.encode("utf-8") if isinstance(content, str) else content
        files = {"file": (filename, data_bytes, "text/markdown")}
        payload: dict[str, Any] = {}
        if metadata is not None:
            payload["metadata"] = json.dumps(metadata)

        resp = self._client.post("/api/v1/files/", files=files, data=payload)
        resp.raise_for_status()
        body = resp.json()
        if not body or "id" not in body:
            raise RuntimeError(f"upload_file returned no id: {body!r}")
        return body["id"]

    def attach_file(self, knowledge_id: str, file_id: str) -> dict[str, Any]:
        resp = self._client.post(
            f"/api/v1/knowledge/{knowledge_id}/file/add",
            json={"file_id": file_id},
        )
        resp.raise_for_status()
        return resp.json() or {}

    def delete_file(self, file_id: str) -> bool:
        """Delete a file by id. Returns True on success or 404 (already gone).

        Deleting a file also removes it from any knowledge it was attached
        to, so we don't need a separate /file/remove call on the knowledge.
        """
        resp = self._client.delete(f"/api/v1/files/{file_id}")
        if resp.status_code == 404:
            return True
        try:
            resp.raise_for_status()
        except httpx.HTTPStatusError as exc:
            log.warning("delete_file(%s) failed: %s", file_id, exc)
            return False
        return True

    # ── composite: idempotent upsert by external_id ──────────────────
    def push(
        self,
        *,
        knowledge_name: str,
        external_id: str,
        filename: str,
        content: bytes | str,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Idempotent upsert: if `external_id` was pushed before, delete
        the old file first, then upload+attach the new one.

        Returns a dict summarizing what happened, useful for graph state.
        """
        kb_id = self.ensure_knowledge(knowledge_name)

        replaced = False
        prior = self.state.get_file_id(external_id)
        if prior:
            self.delete_file(prior)
            self.state.forget_file_id(external_id)
            replaced = True

        # Merge the external_id into metadata so it's inspectable in
        # Open WebUI's UI if it ever exposes doc-level meta.
        meta = dict(metadata or {})
        meta["external_id"] = external_id

        file_id = self.upload_file(filename=filename, content=content, metadata=meta)
        attach = self.attach_file(kb_id, file_id)
        self.state.set_file_id(external_id, file_id)
        self.state.save()
        return {
            "external_id": external_id,
            "knowledge_name": knowledge_name,
            "knowledge_id": kb_id,
            "file_id": file_id,
            "replaced": replaced,
            "attach_response": attach,
        }

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> OpenWebUIClient:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


def build_push_payload(
    *,
    knowledge_name: str,
    external_id: str,
    filename: str,
    content: bytes | str,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Structured preview of what push() would send — used by tests."""
    body = content.encode("utf-8") if isinstance(content, str) else content
    meta = dict(metadata or {})
    meta["external_id"] = external_id
    return {
        "ensure_knowledge": {
            "method": "POST",
            "path": "/api/v1/knowledge/create",
            "json": {
                "name": knowledge_name,
                "description": f"(seed) {knowledge_name}",
            },
        },
        "delete_prior_if_any": {
            "method": "DELETE",
            "path": "/api/v1/files/{prior_file_id}",
            "when": "state.external_ids contains external_id",
        },
        "upload_file": {
            "method": "POST",
            "path": "/api/v1/files/",
            "multipart": {
                "file": {
                    "filename": filename,
                    "content_type": "text/markdown",
                    "size_bytes": len(body),
                },
                "metadata": meta,
            },
        },
        "attach_file": {
            "method": "POST",
            "path": "/api/v1/knowledge/{knowledge_id}/file/add",
            "json": {"file_id": "<from upload_file>"},
        },
    }
