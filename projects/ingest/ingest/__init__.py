"""Declarative ingestion pipeline for personal/IT knowledge.

Three source adapters (obsidian vault repo via GitHub Contents API,
Atlassian Cloud Jira+Confluence, arbitrary GitHub repos) feed one sink
(Open WebUI Knowledge API) through LangGraph graphs. All sources are
pull-over-API — nothing on disk is required.
"""

__version__ = "0.2.0"
