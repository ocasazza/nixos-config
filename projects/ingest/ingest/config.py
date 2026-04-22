"""Env-driven configuration (pydantic-settings).

All sources pull over API — no local vault path is required. The
NixOS module renders env vars into each systemd unit's Environment=;
local dev loads them from `.env` via direnv. Every knob that changes
between hosts flows through here — NOT hardcoded anywhere else in the
package.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


# Canonical vault-path-glob → knowledge routing. Keys are glob-like
# prefix patterns (no `**` handling — a simple `path == glob or
# path.startswith(glob + "/")` match, with the glob having trailing
# `/**/*.md` stripped on load). Matches the spec; overridable via
# env INGEST_OBSIDIAN_FOLDER_MAP (JSON) for per-host reshaping.
DEFAULT_OBSIDIAN_FOLDER_MAP: dict[str, str] = {
    "vault/10-Journal": "kb-notes-personal",
    "vault/20-Research-Hub": "kb-notes-personal",
    "vault/30-Knowledge-Base/IT-Ops": "kb-it-docs",
    "vault/30-Knowledge-Base/Architecture": "kb-systems-internal",
    "vault/30-Knowledge-Base/Hardware": "kb-systems-external",
    "vault/30-Knowledge-Base/Tools-and-Links": "kb-systems-external",
}

# Descriptions seeded on first-run knowledge creation (idempotent —
# Open WebUI's /api/v1/knowledge/create is keyed by name).
DEFAULT_KNOWLEDGE_DESCRIPTIONS: dict[str, str] = {
    "kb-it-tickets": "IT tickets pulled from Jira + GitHub issues",
    "kb-it-docs": "IT runbooks, Confluence, and vault IT-Ops notes",
    "kb-notes-personal": "Personal notes, journal, research from vault",
    "kb-notes-meetings": "Meeting transcripts and action items",
    "kb-systems-internal": "Internal system design/config/maintenance docs",
    "kb-systems-external": "External vendor/upstream docs",
}


class GithubRepoSpec(BaseSettings):
    """One entry in INGEST_GITHUB_REPOS (JSON list).

    Env shape (set by the NixOS module):
        INGEST_GITHUB_REPOS='[{"slug":"ocasazza/nixos-config","kind":"internal",
                               "includeIssues":false,"includePRs":false,
                               "includeDocs":true,
                               "docsPaths":["docs","README.md"]}]'
    """

    slug: str
    kind: str = "internal"  # "internal" | "external"
    include_issues: bool = Field(default=True, alias="includeIssues")
    include_prs: bool = Field(default=True, alias="includePRs")
    include_docs: bool = Field(default=True, alias="includeDocs")
    docs_paths: list[str] = Field(
        default_factory=lambda: ["docs", "README.md"], alias="docsPaths"
    )

    model_config = SettingsConfigDict(populate_by_name=True, extra="ignore")


class Settings(BaseSettings):
    """Runtime settings. Env vars are prefixed `INGEST_`."""

    model_config = SettingsConfigDict(
        env_prefix="INGEST_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ── paths ────────────────────────────────────────────────────────
    state_dir: Path = Field(
        default=Path("/var/lib/ingest"),
        description="Persistent state (knowledge-id map, last-sync cursors, external_id → file_id).",
    )

    # ── Open WebUI sink ──────────────────────────────────────────────
    openwebui_url: str = Field(
        default="http://localhost:8080",
        description="Base URL of the Open WebUI instance.",
    )
    openwebui_token: str = Field(
        default="",
        description="Open WebUI API token (generated in UI → Settings → Account).",
    )

    # ── obsidian source (GitHub Contents API) ────────────────────────
    obsidian_repo: str = Field(
        default="ocasazza/obsidian",
        description="GitHub slug of the vault repo.",
    )
    obsidian_branch: str = Field(
        default="main",
        description="Branch to pull from.",
    )
    obsidian_token: str = Field(
        default="",
        description="GitHub PAT for the vault repo. Empty = try unauthenticated (works for public repos).",
    )
    obsidian_folder_map: dict[str, str] = Field(
        default_factory=lambda: dict(DEFAULT_OBSIDIAN_FOLDER_MAP),
        description="Vault path prefix → Open WebUI knowledge name.",
    )

    # ── Atlassian source ─────────────────────────────────────────────
    atlassian_base_url: str = Field(
        default="",
        description="Atlassian Cloud base URL, e.g. https://foo.atlassian.net",
    )
    atlassian_email: str = Field(
        default="",
        description="Atlassian account email (for basic auth).",
    )
    atlassian_api_token: str = Field(
        default="",
        description="Atlassian API token.",
    )
    atlassian_jira_projects: list[str] = Field(
        default_factory=list,
        description="Jira project keys to sync (empty = all accessible).",
    )
    atlassian_confluence_spaces: list[str] = Field(
        default_factory=list,
        description="Confluence space keys to sync (empty = all accessible).",
    )
    atlassian_tickets_knowledge: str = Field(
        default="kb-it-tickets",
        description="Knowledge name Jira issues land in.",
    )
    atlassian_docs_knowledge: str = Field(
        default="kb-it-docs",
        description="Knowledge name Confluence pages land in.",
    )

    # ── GitHub source (issues / PRs / repo docs) ─────────────────────
    github_token: str = Field(
        default="",
        description="GitHub PAT (classic or fine-grained) with repo + read:org.",
    )
    github_repos: list[GithubRepoSpec] = Field(
        default_factory=list,
        description="Repos to index. Env: JSON list.",
    )
    github_tickets_knowledge: str = Field(
        default="kb-it-tickets",
        description="Knowledge name issues + PRs land in (shared with Jira).",
    )
    github_docs_internal_knowledge: str = Field(
        default="kb-systems-internal",
        description="Knowledge name docs from internal repos land in.",
    )
    github_docs_external_knowledge: str = Field(
        default="kb-systems-external",
        description="Knowledge name docs from external repos land in.",
    )

    # ── observability ────────────────────────────────────────────────
    phoenix_endpoint: str = Field(
        default="http://localhost:6006/v1/traces",
        description="Phoenix OTLP HTTP endpoint.",
    )

    # ── behavior ─────────────────────────────────────────────────────
    initial_backfill_days: int = Field(
        default=30,
        description="On first run (empty state), go back this far per source.",
    )

    @field_validator("github_repos", mode="before")
    @classmethod
    def _parse_github_repos(cls, v: Any) -> Any:
        if isinstance(v, str):
            if not v.strip():
                return []
            try:
                parsed = json.loads(v)
            except json.JSONDecodeError:
                return []
            return parsed if isinstance(parsed, list) else []
        return v

    @field_validator("obsidian_folder_map", "atlassian_jira_projects", "atlassian_confluence_spaces", mode="before")
    @classmethod
    def _parse_json_field(cls, v: Any) -> Any:
        if isinstance(v, str):
            s = v.strip()
            if not s:
                # NixOS module emits "" for empty lists; pydantic needs None/empty.
                return []
            if s.startswith("{") or s.startswith("["):
                try:
                    return json.loads(s)
                except json.JSONDecodeError:
                    return v
            # CSV fallback for list-of-str fields (atlassian_*_projects|spaces).
            if "," in s:
                return [p.strip() for p in s.split(",") if p.strip()]
            return [s]
        return v

    # ── helpers ──────────────────────────────────────────────────────
    def resolve_knowledge_description(self, name: str) -> str:
        return DEFAULT_KNOWLEDGE_DESCRIPTIONS.get(name, f"Ingested into {name}")

    def obsidian_knowledge_for_path(self, vault_path: str) -> str | None:
        """Given a path inside the obsidian repo (e.g. `vault/10-Journal/2026-04-21.md`),
        return the target knowledge name or None if the path is outside the configured map.

        Longest-prefix-wins so e.g. `vault/30-Knowledge-Base/IT-Ops/foo.md` resolves
        to `kb-it-docs` not any shorter `vault/30-Knowledge-Base/...` sibling.
        """
        candidates = sorted(self.obsidian_folder_map.keys(), key=len, reverse=True)
        for prefix in candidates:
            if vault_path == prefix or vault_path.startswith(prefix + "/"):
                return self.obsidian_folder_map[prefix]
        return None


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings


def reset_settings_for_tests(**overrides: Any) -> Settings:
    """Reset the process-level singleton (test use only)."""
    global _settings
    _settings = Settings(**overrides)
    return _settings
