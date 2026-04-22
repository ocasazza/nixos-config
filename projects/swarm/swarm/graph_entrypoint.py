"""LangGraph Server entrypoint.

The server's `langgraph.json` references a graph factory. Our `build_graph`
requires a `SwarmConfig` arg that we derive from env, so we wrap it in a
zero-arg factory the server can call.
"""

from __future__ import annotations

from swarm.config import load
from swarm.graph import build_graph


def make_graph():
    """Factory called by `langgraph dev` for each run."""
    return build_graph(load())
