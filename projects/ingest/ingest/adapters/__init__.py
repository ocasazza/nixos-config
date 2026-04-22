"""Source adapters — all pull-over-API.

- obsidian: the user's Obsidian vault lives in `ocasazza/obsidian` on
  GitHub; we pull via the Contents API (not a tarball) so we can issue
  conditional requests and keep diffs incremental.
- atlassian: Jira + Confluence via Atlassian Cloud.
- github: issues, PRs, and repo docs for an arbitrary list of repos.
"""
