"""Demo multi-backend graph. 'coder-remote' points at exo/GFR backends;
this graph can only complete end-to-end once those are reachable.
Until then expect cooldown-quarantine on the first expand call.

Shape (three phases, split across model groups):

    START
      │
      ▼
    plan      (coder-local, single call)
      │
      ▼
    ┌─── fan-out ────────────────────────────┐
    │                                        │
    expand   expand   expand   ...           │   (coder-remote, N parallel)
    │   │     │         │                    │
    └─── collect via Annotated reducer ──────┘
      │
      ▼
    reduce    (coder-local, single call)
      │
      ▼
    END

The plan phase asks `coder-local` (luna vLLM, the always-on anchor) to
enumerate the fan-out grid. The expand phase then ships N independent
worker calls over `coder-remote`, which LiteLLM routes across the exo
cluster / GFR federation. The reduce phase comes back to `coder-local`
because synthesizing N worker outputs into a single answer is
latency-sensitive and we want the fast local path for it.

Concrete task this graph solves end-to-end:

    "Compare 3 programming languages on 3 dimensions."

The planner emits the 3×3 grid (9 cells). Each of the 9 cells runs as
its own `Send`-dispatched expand worker on `coder-remote`. The reducer
stitches the 9 judgements into a single comparison table on
`coder-local`.
"""

from __future__ import annotations

import json
import os
from typing import Annotated, Any, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.constants import Send
from langgraph.graph import END, START, StateGraph

from swarm import telemetry
from swarm.config import SwarmConfig, load

# Default 3x3 grid the planner falls back to if the coder-local call
# returns junk JSON. Keeps the demo graph runnable in Studio even when
# the plan model misbehaves. The shape mirrors what the planner prompt
# asks for so the fan-out / reducer don't need a separate code path.
DEFAULT_LANGUAGES = ["Python", "Rust", "TypeScript"]
DEFAULT_DIMENSIONS = [
    "type system expressiveness",
    "runtime performance",
    "ecosystem maturity",
]


def _reduce_list(left: list[Any], right: list[Any]) -> list[Any]:
    """Concatenating reducer — parallel expand workers append their
    cell judgements into a single results list."""
    return (left or []) + (right or [])


class DemoState(TypedDict, total=False):
    task: str
    languages: list[str]
    dimensions: list[str]
    cells: Annotated[list[dict[str, Any]], _reduce_list]
    answer: str


class CellState(TypedDict):
    task: str
    language: str
    dimension: str


PLAN_SYSTEM = """You plan a comparison grid for a multi-backend LangGraph
demo. The user gives you a task like "Compare 3 programming languages on
3 dimensions". Pick exactly 3 languages and exactly 3 dimensions (short
noun phrases, no sentences). Return STRICT JSON, nothing else:

{{
  "languages":  ["L1", "L2", "L3"],
  "dimensions": ["D1", "D2", "D3"]
}}
"""

EXPAND_SYSTEM = """You evaluate ONE programming language on ONE dimension.
Respond in 2-3 sentences of concrete, opinionated prose. No headings, no
bullet lists — just the paragraph. Be honest about weaknesses."""

REDUCE_SYSTEM = """You are the reducer for a language-vs-dimension
comparison grid. You receive the original task, the chosen languages,
the chosen dimensions, and a list of per-cell judgements. Synthesize
a single Markdown comparison table (rows = languages, columns =
dimensions) followed by a one-paragraph verdict. Cite each cell's
(language, dimension) pair where it informs the verdict."""


def build_demo_graph(cfg: SwarmConfig):
    # Phase backends — bound to LiteLLM model-group names, NOT raw HF
    # ids. LiteLLM's router resolves the group to a live deployment.
    # See `litellm_config.yaml` for the coder-local / coder-remote
    # split.
    local_llm = ChatOpenAI(
        model="coder-local",
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.2,
    )
    remote_llm = ChatOpenAI(
        model="coder-remote",
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.3,
    )

    async def plan(state: DemoState) -> DemoState:
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=PLAN_SYSTEM),
                HumanMessage(content=state["task"]),
            ]
        )
        languages, dimensions = _parse_grid(msg.content)
        return {"languages": languages, "dimensions": dimensions}

    async def expand(state: CellState) -> DemoState:
        language = state["language"]
        dimension = state["dimension"]
        msg = await remote_llm.ainvoke(
            [
                SystemMessage(content=EXPAND_SYSTEM),
                HumanMessage(
                    content=f"Language: {language}\nDimension: {dimension}\n\nEvaluate."
                ),
            ]
        )
        return {
            "cells": [
                {
                    "language": language,
                    "dimension": dimension,
                    "judgement": msg.content,
                }
            ]
        }

    async def reduce(state: DemoState) -> DemoState:
        bundle = json.dumps(
            {
                "languages": state.get("languages", []),
                "dimensions": state.get("dimensions", []),
                "cells": state.get("cells", []),
            },
            indent=2,
            default=str,
        )
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=REDUCE_SYSTEM),
                HumanMessage(
                    content=f"Original task:\n{state['task']}\n\nGrid:\n{bundle}"
                ),
            ]
        )
        return {"answer": msg.content}

    def fanout(state: DemoState) -> list[Send]:
        languages = state.get("languages") or DEFAULT_LANGUAGES
        dimensions = state.get("dimensions") or DEFAULT_DIMENSIONS
        return [
            Send(
                "expand",
                {
                    "task": state["task"],
                    "language": language,
                    "dimension": dimension,
                },
            )
            for language in languages
            for dimension in dimensions
        ]

    graph = StateGraph(DemoState)
    graph.add_node("plan", plan)
    graph.add_node("expand", expand)
    graph.add_node("reduce", reduce)

    graph.add_edge(START, "plan")
    graph.add_conditional_edges("plan", fanout, ["expand"])
    graph.add_edge("expand", "reduce")
    graph.add_edge("reduce", END)

    return graph.compile().with_config({"max_concurrency": cfg.max_parallel_agents})


def _parse_grid(raw: str | list) -> tuple[list[str], list[str]]:
    """Tolerate JSON wrapped in markdown fences. Fall back to the
    default 3x3 grid if parsing fails so the demo still runs."""
    text = (
        raw
        if isinstance(raw, str)
        else "".join(
            part.get("text", "") if isinstance(part, dict) else str(part) for part in raw
        )
    )
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1] if text.count("```") >= 2 else text
        if text.startswith("json"):
            text = text[4:]
        text = text.strip("`\n ")
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return DEFAULT_LANGUAGES, DEFAULT_DIMENSIONS
    if not isinstance(obj, dict):
        return DEFAULT_LANGUAGES, DEFAULT_DIMENSIONS
    languages = obj.get("languages") or DEFAULT_LANGUAGES
    dimensions = obj.get("dimensions") or DEFAULT_DIMENSIONS
    if not isinstance(languages, list) or not isinstance(dimensions, list):
        return DEFAULT_LANGUAGES, DEFAULT_DIMENSIONS
    return (
        [str(x) for x in languages[:3]],
        [str(x) for x in dimensions[:3]],
    )


def make_graph():
    """Factory called by `langgraph dev` for each run."""
    cfg = load()
    # Attach OpenInference instrumentors so Phoenix sees this run.
    # `init` is idempotent and a no-op on repeat calls.
    telemetry.init(
        cfg.phoenix_endpoint,
        service_name=os.environ.get("OTEL_SERVICE_NAME", "swarm-demo"),
    )
    return build_demo_graph(cfg)
