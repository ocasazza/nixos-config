"""Obsidian vault adapter — pulls markdown from a GitHub repo.

The user's vault lives in a dedicated GitHub repo (default
`ocasazza/obsidian`). We pull markdown files via the GitHub Git Trees
API (for listing) + Contents API (for fetching individual files). This
is bandwidth-efficient vs. downloading the repo tarball every run, and
lets us go incremental via the tree's commit sha.

Incremental sync strategy:

    1. GET /repos/{repo}/commits/{branch}     → head commit sha
       If unchanged since last run, skip the whole thing.
    2. GET /repos/{repo}/git/trees/{sha}?recursive=1
       Yields every file blob with path + sha. The blob sha only changes
       when the file content changes, so we diff against the per-path
       shas from the prior run's state.
    3. For each path whose (a) prefix matches a configured folder map
       and (b) sha differs from state → GET /repos/{repo}/contents/{path}
       and push.

Paths removed since the last run are tracked via `deleted = prior_paths
- current_paths`; we delete the corresponding file from Open WebUI via
external_id.

Frontmatter handling: stripped before push; non-empty fields are merged
into the sink's metadata payload. If the Open WebUI UI ever surfaces
doc meta, it'll be visible there. A compact header summarizing a few
key fields (title / tags / date) is prepended to the body too, so the
search-index includes them even if the UI ignores the metadata blob.
"""

from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from typing import Any, Iterator

import frontmatter
import httpx

from ingest.config import Settings, get_settings
from ingest.state import IngestState

log = logging.getLogger(__name__)


GITHUB_API = "https://api.github.com"
_STATE_NS = "obsidian"
# How many paths we'll drop into Open WebUI in a single run before
# yielding control (soft cap — each run is already gated by the systemd
# timer, this just avoids pathological backfills).
_MAX_FILES_PER_RUN = 500


@dataclass(slots=True)
class ObsidianDoc:
    external_id: str
    knowledge_name: str
    vault_path: str
    filename: str
    content: str  # markdown body (frontmatter stripped)
    metadata: dict[str, Any]
    blob_sha: str


class GithubContentsClient:
    """Thin httpx wrapper for the subset of the GitHub REST API we need."""

    def __init__(
        self,
        *,
        repo: str,
        branch: str,
        token: str | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        self.repo = repo
        self.branch = branch
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ingest/obsidian",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        self._client = http_client or httpx.Client(
            base_url=GITHUB_API,
            headers=headers,
            timeout=30.0,
        )

    def head_commit_sha(self) -> str:
        resp = self._client.get(f"/repos/{self.repo}/commits/{self.branch}")
        resp.raise_for_status()
        return resp.json()["sha"]

    def tree(self, commit_sha: str) -> list[dict[str, Any]]:
        """Recursive tree listing. Returns the raw `tree` array."""
        # Use commit sha directly — the git trees API accepts either a
        # tree sha or a commit sha (it follows commit → tree).
        resp = self._client.get(
            f"/repos/{self.repo}/git/trees/{commit_sha}",
            params={"recursive": "1"},
        )
        resp.raise_for_status()
        body = resp.json()
        if body.get("truncated"):
            log.warning(
                "repo tree %s@%s truncated by GitHub — fall back to `git clone` if the vault gets much bigger",
                self.repo,
                commit_sha,
            )
        return body.get("tree", []) or []

    def blob(self, sha: str) -> bytes:
        """Fetch a blob by sha. Handles base64 for binary-safe returns."""
        resp = self._client.get(f"/repos/{self.repo}/git/blobs/{sha}")
        resp.raise_for_status()
        body = resp.json()
        encoding = body.get("encoding", "base64")
        content = body.get("content", "")
        if encoding == "base64":
            return base64.b64decode(content)
        return content.encode("utf-8")

    def close(self) -> None:
        self._client.close()


def _external_id(vault_path: str) -> str:
    return f"obsidian:{vault_path}"


def _parse_frontmatter(raw_text: str) -> tuple[str, dict[str, Any]]:
    try:
        post = frontmatter.loads(raw_text)
        return post.content, dict(post.metadata)
    except Exception:  # noqa: BLE001
        return raw_text, {}


def _build_doc(
    *,
    vault_path: str,
    blob_sha: str,
    body_bytes: bytes,
    knowledge_name: str,
    repo: str,
    branch: str,
) -> ObsidianDoc:
    raw = body_bytes.decode("utf-8", errors="replace")
    body, fm = _parse_frontmatter(raw)

    title = str(fm.get("title") or vault_path.rsplit("/", 1)[-1].removesuffix(".md"))
    tags = fm.get("tags") or []
    date = fm.get("date") or fm.get("created") or ""

    # Prepend a short header so tokenization includes the meta even if
    # Open WebUI's UI doesn't render metadata blobs. Keep it compact —
    # just title + tags + date line, nothing else.
    header_lines = [f"# {title}"]
    if tags:
        tag_str = ", ".join(map(str, tags)) if isinstance(tags, list) else str(tags)
        header_lines.append(f"_tags: {tag_str}_")
    if date:
        header_lines.append(f"_date: {date}_")
    header = "\n".join(header_lines) + "\n\n"

    # Use `/`-joined path under the repo as the filename so Open WebUI's
    # listing is browsable. Replace `/` with `__` since the Files API
    # treats filenames as opaque strings and we want a single segment.
    filename = vault_path.replace("/", "__")

    return ObsidianDoc(
        external_id=_external_id(vault_path),
        knowledge_name=knowledge_name,
        vault_path=vault_path,
        filename=filename,
        content=header + body,
        metadata={
            "source": "obsidian",
            "repo": repo,
            "branch": branch,
            "vault_path": vault_path,
            "title": title,
            "blob_sha": blob_sha,
            **{k: v for k, v in fm.items() if _jsonish(v)},
        },
        blob_sha=blob_sha,
    )


def _jsonish(v: Any) -> bool:
    """Filter non-JSON-safe frontmatter values (datetimes, etc.)."""
    if v is None or isinstance(v, (bool, int, float, str)):
        return True
    if isinstance(v, (list, tuple)):
        return all(_jsonish(i) for i in v)
    if isinstance(v, dict):
        return all(isinstance(k, str) and _jsonish(val) for k, val in v.items())
    return False


def iter_changed_docs(
    *,
    settings: Settings | None = None,
    state: IngestState | None = None,
) -> Iterator[tuple[str, ObsidianDoc | None, str | None]]:
    """Yield `(event, doc, vault_path)` tuples:

        ("add",    ObsidianDoc, None)       → new or updated file
        ("delete", None,       vault_path)  → file gone since last run
    """
    settings = settings or get_settings()
    state = state or IngestState(settings.state_dir)

    client = GithubContentsClient(
        repo=settings.obsidian_repo,
        branch=settings.obsidian_branch,
        token=settings.obsidian_token or None,
    )
    try:
        head_sha = client.head_commit_sha()
        last_head = state.get_cursor(_STATE_NS, "head_sha")
        if last_head == head_sha:
            log.info("obsidian: head sha unchanged (%s) — skipping pull", head_sha)
            return

        tree = client.tree(head_sha)
        current: dict[str, str] = {}  # vault_path → blob_sha
        for entry in tree:
            if entry.get("type") != "blob":
                continue
            path = entry.get("path") or ""
            if not path.endswith(".md"):
                continue
            current[path] = entry.get("sha", "")

        prior: dict[str, str] = state.get_cursor(_STATE_NS, "blob_shas", {}) or {}

        # Additions + updates — only for paths that map to a knowledge.
        count = 0
        for path, blob_sha in current.items():
            knowledge = settings.obsidian_knowledge_for_path(path)
            if knowledge is None:
                continue
            if prior.get(path) == blob_sha:
                continue
            if count >= _MAX_FILES_PER_RUN:
                log.warning("obsidian: hit _MAX_FILES_PER_RUN=%d — deferring the rest to next run", _MAX_FILES_PER_RUN)
                break
            try:
                raw = client.blob(blob_sha)
            except httpx.HTTPError as exc:
                log.warning("obsidian: blob fetch failed for %s (%s) — skipping", path, exc)
                continue
            doc = _build_doc(
                vault_path=path,
                blob_sha=blob_sha,
                body_bytes=raw,
                knowledge_name=knowledge,
                repo=settings.obsidian_repo,
                branch=settings.obsidian_branch,
            )
            yield ("add", doc, None)
            count += 1

        # Deletions — files that mapped to a knowledge last run but are
        # gone now. We only emit delete events for paths present in
        # prior; that way a one-time folder-map flip doesn't mass-delete
        # valid content.
        for path in sorted(prior.keys()):
            if path in current:
                continue
            if settings.obsidian_knowledge_for_path(path) is None:
                continue
            yield ("delete", None, path)
    finally:
        client.close()


def update_cursors_after_run(
    *,
    head_sha: str,
    blob_shas: dict[str, str],
    state: IngestState,
) -> None:
    """Commit the tree state atomically at the END of a graph run — not
    during, so an interrupted run retries cleanly next time."""
    state.set_cursor(_STATE_NS, "head_sha", head_sha)
    state.set_cursor(_STATE_NS, "blob_shas", blob_shas)
    state.save()


def collect_current_tree(settings: Settings | None = None) -> tuple[str, dict[str, str]]:
    """Return `(head_sha, path→blob_sha)` for the current tree. Convenience
    for the graph's post-push cursor update; doesn't re-fetch bodies."""
    settings = settings or get_settings()
    client = GithubContentsClient(
        repo=settings.obsidian_repo,
        branch=settings.obsidian_branch,
        token=settings.obsidian_token or None,
    )
    try:
        head_sha = client.head_commit_sha()
        tree = client.tree(head_sha)
        mapping: dict[str, str] = {}
        for entry in tree:
            if entry.get("type") != "blob":
                continue
            path = entry.get("path") or ""
            if not path.endswith(".md"):
                continue
            mapping[path] = entry.get("sha", "")
        return head_sha, mapping
    finally:
        client.close()
