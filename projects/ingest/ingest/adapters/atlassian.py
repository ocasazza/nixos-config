"""Atlassian Cloud adapter — Jira + Confluence → Open WebUI.

Pull-over-API, sink-direct. Incremental via `updated >= -PT30M` JQL
for Jira and `lastmodified >= now(-30m)` CQL for Confluence, with a
per-project/space cursor in state.json. First run with no cursor
backfills `settings.initial_backfill_days` days.

External-id shapes:
    jira:<PROJECT-KEY>-<NUM>
    confluence:<SPACE>:<PAGE-ID>

Both flows render markdown in memory and hand it straight to the
sink's idempotent push() — no local files, no vault round trip.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Iterator

from atlassian import Confluence, Jira  # type: ignore[import-untyped]

from ingest.config import Settings, get_settings
from ingest.state import IngestState

log = logging.getLogger(__name__)


_STATE_NS_JIRA = "atlassian:jira"
_STATE_NS_CONF = "atlassian:confluence"
_UNSAFE = re.compile(r"[^A-Za-z0-9._-]+")


@dataclass(slots=True)
class AtlassianDoc:
    external_id: str
    knowledge_name: str
    filename: str
    content: str
    metadata: dict[str, Any]
    updated: str  # ISO8601 — used to advance the cursor


# ── Jira ─────────────────────────────────────────────────────────────


def _adf_to_markdown(adf: dict[str, Any]) -> str:
    """Very naive ADF (Atlassian Document Format) → markdown. Full
    fidelity is out of scope; we just want searchable text."""
    out: list[str] = []

    def _walk(node: Any) -> None:
        if isinstance(node, dict):
            t = node.get("type")
            if t == "text":
                out.append(node.get("text", ""))
                return
            if t in ("paragraph", "heading"):
                for child in node.get("content", []):
                    _walk(child)
                out.append("\n\n")
                return
            if t == "hardBreak":
                out.append("\n")
                return
            for child in node.get("content", []) or []:
                _walk(child)
        elif isinstance(node, list):
            for item in node:
                _walk(item)

    _walk(adf)
    return "".join(out).strip()


def render_jira_issue(issue: dict[str, Any]) -> AtlassianDoc:
    fields = issue.get("fields", {}) or {}
    key = issue.get("key", "UNKNOWN")
    summary = (fields.get("summary") or "").strip()
    status = ((fields.get("status") or {}).get("name") or "").strip()
    priority = ((fields.get("priority") or {}).get("name") or "").strip()
    assignee_obj = fields.get("assignee") or {}
    assignee = assignee_obj.get("displayName") or assignee_obj.get("name") or "unassigned"
    reporter_obj = fields.get("reporter") or {}
    reporter = reporter_obj.get("displayName") or reporter_obj.get("name") or "unknown"
    issue_type = ((fields.get("issuetype") or {}).get("name") or "").strip()
    updated = fields.get("updated", "")

    description = fields.get("description") or ""
    if isinstance(description, dict):
        description = _adf_to_markdown(description)

    comments_block = ""
    comment_container = fields.get("comment") or {}
    comments = comment_container.get("comments", []) if isinstance(comment_container, dict) else []
    if comments:
        lines = ["## Comments", ""]
        for c in comments:
            author = ((c.get("author") or {}).get("displayName")) or "unknown"
            created = c.get("created", "")
            body = c.get("body") or ""
            if isinstance(body, dict):
                body = _adf_to_markdown(body)
            lines.append(f"### {author} — {created}")
            lines.append("")
            lines.append(str(body).strip())
            lines.append("")
        comments_block = "\n".join(lines)

    body_md = "\n".join(
        [
            f"# {key}: {summary}",
            "",
            f"- **Status:** {status}",
            f"- **Priority:** {priority}",
            f"- **Type:** {issue_type}",
            f"- **Assignee:** {assignee}",
            f"- **Reporter:** {reporter}",
            f"- **Updated:** {updated}",
            "",
            "## Description",
            "",
            str(description).strip() or "_(no description)_",
            "",
            comments_block,
        ]
    )
    return AtlassianDoc(
        external_id=f"jira:{key}",
        knowledge_name="",  # caller fills in
        filename=f"{key}.md",
        content=body_md,
        metadata={
            "source": "jira",
            "source_id": key,
            "jira_key": key,
            "title": f"{key}: {summary}",
            "status": status,
            "priority": priority,
            "issue_type": issue_type,
            "assignee": assignee,
            "reporter": reporter,
            "updated": updated,
        },
        updated=updated,
    )


def pull_jira(
    *,
    settings: Settings | None = None,
    state: IngestState | None = None,
) -> Iterator[AtlassianDoc]:
    settings = settings or get_settings()
    state = state or IngestState(settings.state_dir)

    if not (settings.atlassian_base_url and settings.atlassian_email and settings.atlassian_api_token):
        log.warning("atlassian credentials missing — skipping jira pull")
        return

    jira = Jira(
        url=settings.atlassian_base_url,
        username=settings.atlassian_email,
        password=settings.atlassian_api_token,
        cloud=True,
    )

    projects = settings.atlassian_jira_projects or [""]
    for proj in projects:
        cursor_key = proj or "_all_"
        last = state.get_cursor(_STATE_NS_JIRA, cursor_key)
        floor = last or _backfill_floor(settings).strftime("%Y-%m-%d %H:%M")
        jql_parts = [f'updated >= "{floor}"']
        if proj:
            jql_parts.insert(0, f"project = {proj}")
        jql = " AND ".join(jql_parts) + " ORDER BY updated ASC"
        log.info("JQL: %s", jql)

        start = 0
        max_updated = last
        while True:
            result = jira.jql(
                jql,
                start=start,
                limit=50,
                fields="summary,status,priority,issuetype,assignee,reporter,updated,description,comment",
                expand="renderedFields",
            )
            issues = (result or {}).get("issues", [])
            if not issues:
                break
            for issue in issues:
                doc = render_jira_issue(issue)
                doc.knowledge_name = settings.atlassian_tickets_knowledge
                yield doc
                if doc.updated and (max_updated is None or doc.updated > max_updated):
                    max_updated = doc.updated
            if len(issues) < 50:
                break
            start += 50

        if max_updated:
            state.set_cursor(_STATE_NS_JIRA, cursor_key, max_updated[:16].replace("T", " "))
    state.save()


# ── Confluence ───────────────────────────────────────────────────────


def _slug(text: str, limit: int = 80) -> str:
    s = _UNSAFE.sub("-", text.strip()).strip("-")
    return (s[:limit] or "untitled").lower()


def _html_to_markdown(html: str) -> str:
    """Bare-minimum stripper. Real markdownification is out of scope —
    Open WebUI's RAG chunker handles noisy input fine."""
    if not html:
        return ""
    text = re.sub(r"<script.*?</script>", "", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<style.*?</style>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</p>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def render_confluence_page(page: dict[str, Any], space_key: str) -> AtlassianDoc:
    title = page.get("title", "untitled")
    page_id = str(page.get("id", ""))
    body_obj = (page.get("body") or {}).get("view") or (page.get("body") or {}).get("storage") or {}
    body_html = body_obj.get("value") or ""
    body_plain = _html_to_markdown(body_html)
    updated = ((page.get("version") or {}).get("when")) or ""

    md = "\n".join([f"# {title}", "", body_plain, ""])
    filename = f"{space_key}-{_slug(title)}-{page_id}.md"

    return AtlassianDoc(
        external_id=f"confluence:{space_key}:{page_id}",
        knowledge_name="",
        filename=filename,
        content=md,
        metadata={
            "source": "confluence",
            "source_id": page_id,
            "space": space_key,
            "title": title,
            "updated": updated,
        },
        updated=updated,
    )


def pull_confluence(
    *,
    settings: Settings | None = None,
    state: IngestState | None = None,
) -> Iterator[AtlassianDoc]:
    settings = settings or get_settings()
    state = state or IngestState(settings.state_dir)

    if not (settings.atlassian_base_url and settings.atlassian_email and settings.atlassian_api_token):
        log.warning("atlassian credentials missing — skipping confluence pull")
        return

    conf = Confluence(
        url=settings.atlassian_base_url,
        username=settings.atlassian_email,
        password=settings.atlassian_api_token,
        cloud=True,
    )

    spaces = settings.atlassian_confluence_spaces or [""]
    for space in spaces:
        cursor_key = space or "_all_"
        last = state.get_cursor(_STATE_NS_CONF, cursor_key)
        floor_dt = (
            datetime.fromisoformat(last.replace("Z", "+00:00")) if last else _backfill_floor(settings)
        )
        cql_parts = [
            f'lastModified >= "{floor_dt.strftime("%Y-%m-%d %H:%M")}"',
            "type = page",
        ]
        if space:
            cql_parts.insert(0, f'space = "{space}"')
        cql = " AND ".join(cql_parts) + " ORDER BY lastModified ASC"
        log.info("CQL: %s", cql)

        start = 0
        max_when = last
        while True:
            result = conf.cql(
                cql,
                start=start,
                limit=50,
                expand="body.view,version,space",
            )
            results = (result or {}).get("results", [])
            if not results:
                break
            for item in results:
                page = item.get("content") or item
                space_key = (page.get("space") or {}).get("key") or space or "UNK"
                doc = render_confluence_page(page, space_key)
                doc.knowledge_name = settings.atlassian_docs_knowledge
                yield doc
                if doc.updated and (max_when is None or doc.updated > max_when):
                    max_when = doc.updated
            if len(results) < 50:
                break
            start += 50

        if max_when:
            state.set_cursor(_STATE_NS_CONF, cursor_key, max_when)
    state.save()


def _backfill_floor(settings: Settings) -> datetime:
    return datetime.now(tz=UTC) - timedelta(days=settings.initial_backfill_days)
