"""LangGraph Server entrypoint.

The server's `langgraph.json` references a graph factory. Our `build_graph`
requires a `SwarmConfig` arg that we derive from env, so we wrap it in a
zero-arg factory the server can call.

Also kicks off Phoenix tracing here — otherwise `langgraph dev` runs the
graph without OpenInference instrumentors attached and Phoenix never sees
the service. `telemetry.init` is idempotent, so it's safe on every
factory call.
"""

from __future__ import annotations

import os

from swarm import telemetry
from swarm.config import load
from swarm.graph import build_graph


def make_graph():
    """Factory called by `langgraph dev` for each run."""
    cfg = load()
    telemetry.init(
        cfg.phoenix_endpoint,
        service_name=os.environ.get("OTEL_SERVICE_NAME", "swarm"),
    )
    return build_graph(cfg)
