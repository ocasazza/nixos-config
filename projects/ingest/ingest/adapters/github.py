"""GitHub source adapter — issues, PRs, and repo docs.

Pulls from an arbitrary list of repos declared in the NixOS module.
Each repo has a `kind` ("internal" | "external") that steers its docs
into either kb-systems-internal or kb-systems-external. Issues and PRs
always land in the shared ticket bucket (kb-it-tickets), with
`source: github` metadata so downstream consumers can distinguish
them from Jira.

The obsidian VAULT repo is handled by the dedicated `obsidian`
adapter — keep that wiring separate so the folder→knowledge map
stays independently configurable.

Incremental strategy:
    * Issues/PRs: per-repo cursor = ISO8601 timestamp of the last
      issue we processed. On each run we ask the API for issues
      updated since that cursor.
    * Docs:      per-repo cursor = head commit sha (same trick as the
      obsidian adapter). If unchanged, skip; otherwise walk the tree
      and only push docs whose blob sha changed.

External-id shapes:
    github:<owner>/<repo>#<num>
    github-pr:<owner>/<repo>#<num>
    github-doc:<owner>/<repo>/<path>
"""

from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Iterator

import httpx

from ingest.config import GithubRepoSpec, Settings, get_settings
from ingest.state import IngestState

log = logging.getLogger(__name__)


GITHUB_API = "https://api.github.com"
_STATE_NS = "github"


@dataclass(slots=True)
class GithubDoc:
    external_id: str
    knowledge_name: str
    filename: str
    content: str
    metadata: dict[str, Any]


def _client(token: str) -> httpx.Client:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ingest/github",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return httpx.Client(base_url=GITHUB_API, headers=headers, timeout=30.0)


def _backfill_floor(settings: Settings) -> datetime:
    return datetime.now(tz=UTC) - timedelta(days=settings.initial_backfill_days)


# ── issues + PRs ────────────────────────────────────────────────────


def _render_issue(repo_slug: str, issue: dict[str, Any]) -> GithubDoc:
    """Render an issue OR a pull request — GitHub's `/issues` endpoint
    returns both, with PRs distinguished by the presence of
    `pull_request`. We emit different external_id prefixes so a PR and
    an issue with the same number don't collide."""
    number = issue.get("number")
    title = issue.get("title") or ""
    body = issue.get("body") or ""
    user = ((issue.get("user") or {}).get("login")) or "unknown"
    state_ = issue.get("state") or ""
    labels = ", ".join(lbl.get("name", "") for lbl in (issue.get("labels") or []))
    updated = issue.get("updated_at") or ""
    created = issue.get("created_at") or ""
    closed = issue.get("closed_at") or ""
    html_url = issue.get("html_url") or ""
    is_pr = bool(issue.get("pull_request"))

    kind = "github-pr" if is_pr else "github"
    kind_human = "PR" if is_pr else "Issue"

    md = "\n".join(
        [
            f"# {kind_human} #{number}: {title}",
            "",
            f"- **Repo:** {repo_slug}",
            f"- **Author:** {user}",
            f"- **State:** {state_}",
            f"- **Labels:** {labels}",
            f"- **Created:** {created}",
            f"- **Updated:** {updated}",
            f"- **Closed:** {closed}",
            f"- **URL:** {html_url}",
            "",
            "## Body",
            "",
            body.strip() or "_(no body)_",
            "",
        ]
    )
    return GithubDoc(
        external_id=f"{kind}:{repo_slug}#{number}",
        knowledge_name="",  # filled in by caller
        filename=f"{repo_slug.replace('/', '__')}__{kind}-{number}.md",
        content=md,
        metadata={
            "source": "github" if not is_pr else "github-pr",
            "source_id": f"{repo_slug}#{number}",
            "repo": repo_slug,
            "number": number,
            "state": state_,
            "author": user,
            "labels": labels,
            "title": title,
            "updated": updated,
            "url": html_url,
        },
    )


def _pull_issues_for_repo(
    *,
    client: httpx.Client,
    repo: GithubRepoSpec,
    settings: Settings,
    state: IngestState,
) -> Iterator[GithubDoc]:
    if not (repo.include_issues or repo.include_prs):
        return
    cursor_key = repo.slug
    last = state.get_cursor(_STATE_NS + ":issues", cursor_key)
    since = last or _backfill_floor(settings).strftime("%Y-%m-%dT%H:%M:%SZ")
    log.info("github %s: pulling issues since %s", repo.slug, since)

    page = 1
    max_updated = last
    while True:
        resp = client.get(
            f"/repos/{repo.slug}/issues",
            params={
                "state": "all",
                "since": since,
                "per_page": 100,
                "page": page,
                "sort": "updated",
                "direction": "asc",
            },
        )
        if resp.status_code == 404:
            log.warning("github %s: repo not found / no access — skipping", repo.slug)
            return
        resp.raise_for_status()
        issues = resp.json() or []
        if not issues:
            break
        for issue in issues:
            is_pr = bool(issue.get("pull_request"))
            if is_pr and not repo.include_prs:
                continue
            if (not is_pr) and not repo.include_issues:
                continue
            doc = _render_issue(repo.slug, issue)
            doc.knowledge_name = settings.github_tickets_knowledge
            yield doc
            updated = issue.get("updated_at")
            if updated and (max_updated is None or updated > max_updated):
                max_updated = updated
        if len(issues) < 100:
            break
        page += 1

    if max_updated:
        state.set_cursor(_STATE_NS + ":issues", cursor_key, max_updated)


# ── repo docs ────────────────────────────────────────────────────────


def _knowledge_for_docs(repo: GithubRepoSpec, settings: Settings) -> str:
    if repo.kind == "external":
        return settings.github_docs_external_knowledge
    return settings.github_docs_internal_knowledge


def _is_under(path: str, prefix: str) -> bool:
    """prefix can be a file (`README.md`) or a directory (`docs`)."""
    return path == prefix or path.startswith(prefix.rstrip("/") + "/")


def _pull_docs_for_repo(
    *,
    client: httpx.Client,
    repo: GithubRepoSpec,
    settings: Settings,
    state: IngestState,
) -> Iterator[GithubDoc]:
    if not repo.include_docs:
        return

    # Resolve the default branch once. Using the repo endpoint avoids
    # hardcoding `main` / `master`.
    resp = client.get(f"/repos/{repo.slug}")
    if resp.status_code == 404:
        log.warning("github docs %s: repo not found — skipping", repo.slug)
        return
    resp.raise_for_status()
    default_branch = resp.json().get("default_branch", "main")

    head_resp = client.get(f"/repos/{repo.slug}/commits/{default_branch}")
    head_resp.raise_for_status()
    head_sha = head_resp.json().get("sha", "")

    docs_cursor_key = repo.slug
    last_head = state.get_cursor(_STATE_NS + ":docs-head", docs_cursor_key)
    prior_blob_shas: dict[str, str] = state.get_cursor(_STATE_NS + ":docs-shas", docs_cursor_key, {}) or {}
    if last_head == head_sha and prior_blob_shas:
        log.info("github docs %s: head unchanged (%s)", repo.slug, head_sha)
        return

    tree_resp = client.get(
        f"/repos/{repo.slug}/git/trees/{head_sha}",
        params={"recursive": "1"},
    )
    tree_resp.raise_for_status()
    tree = tree_resp.json().get("tree", []) or []

    wanted: list[tuple[str, str]] = []  # (path, blob_sha)
    for entry in tree:
        if entry.get("type") != "blob":
            continue
        path = entry.get("path") or ""
        if not path.endswith((".md", ".mdx", ".rst")):
            # Also allow explicit README at root even without .md suffix? No —
            # stick to textual docs with explicit extensions.
            continue
        if not any(_is_under(path, dp) for dp in repo.docs_paths):
            continue
        wanted.append((path, entry.get("sha", "")))

    current_shas = {p: s for p, s in wanted}
    for path, blob_sha in wanted:
        if prior_blob_shas.get(path) == blob_sha:
            continue
        blob = client.get(f"/repos/{repo.slug}/git/blobs/{blob_sha}")
        blob.raise_for_status()
        body = blob.json()
        encoding = body.get("encoding", "base64")
        raw = body.get("content", "")
        if encoding == "base64":
            text = base64.b64decode(raw).decode("utf-8", errors="replace")
        else:
            text = raw

        yield GithubDoc(
            external_id=f"github-doc:{repo.slug}/{path}",
            knowledge_name=_knowledge_for_docs(repo, settings),
            filename=f"{repo.slug.replace('/', '__')}__{path.replace('/', '__')}",
            content=text,
            metadata={
                "source": "github-doc",
                "source_id": f"{repo.slug}/{path}",
                "repo": repo.slug,
                "path": path,
                "blob_sha": blob_sha,
                "kind": repo.kind,
                "title": path.rsplit("/", 1)[-1],
            },
        )

    # Update cursors at the end — caller's graph saves state explicitly.
    state.set_cursor(_STATE_NS + ":docs-head", docs_cursor_key, head_sha)
    state.set_cursor(_STATE_NS + ":docs-shas", docs_cursor_key, current_shas)


# ── top-level generator ──────────────────────────────────────────────


def iter_docs(
    *,
    settings: Settings | None = None,
    state: IngestState | None = None,
) -> Iterator[GithubDoc]:
    """Yield GithubDoc per repo, across issues + PRs + docs. Caller
    pushes each to the sink and saves state once at the end."""
    settings = settings or get_settings()
    state = state or IngestState(settings.state_dir)

    repos = list(settings.github_repos)
    if not repos:
        log.info("github: no repos configured — nothing to do")
        return

    token = settings.github_token or ""
    with _client(token) as client:
        for repo in repos:
            try:
                yield from _pull_issues_for_repo(
                    client=client, repo=repo, settings=settings, state=state
                )
                yield from _pull_docs_for_repo(
                    client=client, repo=repo, settings=settings, state=state
                )
            except httpx.HTTPError as exc:
                log.warning("github %s: HTTP error (%s) — moving on", repo.slug, exc)
                continue
    state.save()
