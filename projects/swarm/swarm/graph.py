"""LangGraph definition of the swarm.

Shape:

    START → planner → (N parallel workers) → reducer → END

The planner emits a list of subtasks. LangGraph's `Send` API fans those
out in parallel — each one becomes its own worker node invocation with
an isolated state slice. The reducer collects the results and synthesizes
a final answer.

This is the graph the user sees in Phoenix as a trace tree.
"""

from __future__ import annotations

import asyncio
import json
from typing import Annotated, Any, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.constants import Send
from langgraph.graph import END, START, StateGraph

from .agents.browser import run_browser_task
from .agents.vault import run_vault_task
from .config import SwarmConfig


def _reduce_list(left: list[Any], right: list[Any]) -> list[Any]:
    """Concatenating reducer so parallel workers can all append results."""
    return (left or []) + (right or [])


class SwarmState(TypedDict, total=False):
    task: str
    plan: list[dict[str, Any]]
    results: Annotated[list[dict[str, Any]], _reduce_list]
    answer: str


class WorkerState(TypedDict):
    task: str
    subtask: dict[str, Any]


PLANNER_SYSTEM = """You are the planner of a parallel agent swarm.

Break the user's task into independent subtasks that can run concurrently.
Each subtask must be self-contained — a worker will execute it with no
knowledge of the others.

Return STRICT JSON, nothing else:
{{
  "subtasks": [
    {{"id": "s1", "kind": "reason" | "browse" | "vault", "instruction": "..."}},
    ...
  ]
}}

Use "browse" when the subtask requires visiting a website or searching
the live web. Use "reason" for pure-text analysis, coding, or synthesis
that doesn't need external sources.
Use "vault" when the subtask needs to search, list, or read the user's
personal Obsidian knowledge base (notes, journal, prompt library). Vault
access is read-only.
Prefer fewer, higher-quality subtasks over many trivial ones. Hard cap:
{fanout} subtasks.
"""

REDUCER_SYSTEM = """You are the reducer of a parallel agent swarm. You
receive the original task and a list of worker results. Synthesize a
single coherent answer to the original task. Cite which subtask each
piece of information came from using its id."""


def build_graph(cfg: SwarmConfig):
    planner_llm = ChatOpenAI(
        model=cfg.coder_model,
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.2,
    )
    worker_llm = ChatOpenAI(
        model=cfg.coder_model,
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.3,
    )
    reducer_llm = ChatOpenAI(
        model=cfg.coder_model,
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.2,
    )

    async def planner(state: SwarmState) -> SwarmState:
        msg = await planner_llm.ainvoke(
            [
                SystemMessage(content=PLANNER_SYSTEM.format(fanout=cfg.default_fanout)),
                HumanMessage(content=state["task"]),
            ]
        )
        plan = _parse_plan(msg.content, cfg.default_fanout)
        return {"plan": plan}

    async def worker(state: WorkerState) -> SwarmState:
        sub = state["subtask"]
        kind = sub.get("kind", "reason")
        instruction = sub.get("instruction", "")
        sub_id = sub.get("id", "?")

        if kind == "browse":
            output = await run_browser_task(instruction, cfg)
        elif kind == "vault":
            output = await run_vault_task(instruction, cfg)
        else:
            msg = await worker_llm.ainvoke([HumanMessage(content=instruction)])
            output = msg.content

        return {
            "results": [
                {"id": sub_id, "kind": kind, "instruction": instruction, "output": output}
            ]
        }

    async def reducer(state: SwarmState) -> SwarmState:
        # Cap each worker's output before stitching results together so a
        # single chatty worker (most commonly the browser agent, whose
        # raw history serializes to tens of thousands of tokens) can't
        # push the reducer prompt past vLLM's max_model_len. 8k chars
        # (~2k tokens) per worker × default_fanout=8 leaves comfortable
        # headroom inside a 32k-context model for the system prompt,
        # the original task, JSON framing, and the completion budget.
        trimmed = [
            {**r, "output": _truncate(r.get("output", ""), 8000)}
            for r in state.get("results", [])
        ]
        bundle = json.dumps(trimmed, indent=2, default=str)
        msg = await reducer_llm.ainvoke(
            [
                SystemMessage(content=REDUCER_SYSTEM),
                HumanMessage(
                    content=f"Original task:\n{state['task']}\n\nWorker results:\n{bundle}"
                ),
            ]
        )
        return {"answer": msg.content}

    def fanout(state: SwarmState) -> list[Send] | Literal["__end__"]:
        plan = state.get("plan") or []
        if not plan:
            return END  # type: ignore[return-value]
        return [Send("worker", {"task": state["task"], "subtask": s}) for s in plan]

    graph = StateGraph(SwarmState)
    graph.add_node("planner", planner)
    graph.add_node("worker", worker)
    graph.add_node("reducer", reducer)

    graph.add_edge(START, "planner")
    graph.add_conditional_edges("planner", fanout, ["worker", END])
    graph.add_edge("worker", "reducer")
    graph.add_edge("reducer", END)

    # Cap total concurrent worker executions across the graph.
    return graph.compile().with_config({"max_concurrency": cfg.max_parallel_agents})


def _truncate(value: Any, limit: int) -> str:
    """Stringify `value` and cap to `limit` chars with an elided marker.

    Used by the reducer to prevent one runaway worker output from
    blowing the reducer's prompt past the model's context window.
    """
    s = value if isinstance(value, str) else str(value)
    if len(s) <= limit:
        return s
    return s[:limit] + f"\n...[truncated {len(s) - limit} chars]"


def _parse_plan(raw: str | list, cap: int) -> list[dict[str, Any]]:
    """Tolerate JSON wrapped in markdown fences, which smaller models emit."""
    text = raw if isinstance(raw, str) else "".join(
        part.get("text", "") if isinstance(part, dict) else str(part) for part in raw
    )
    text = text.strip()
    if text.startswith("```"):
        # Strip ```json ... ``` fences.
        text = text.split("```", 2)[1] if text.count("```") >= 2 else text
        if text.startswith("json"):
            text = text[4:]
        text = text.strip("`\n ")
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return [{"id": "s1", "kind": "reason", "instruction": text[:2000]}]
    subs = obj.get("subtasks") if isinstance(obj, dict) else obj
    if not isinstance(subs, list):
        return []
    return subs[:cap]


async def run(task: str, cfg: SwarmConfig) -> dict[str, Any]:
    graph = build_graph(cfg)
    return await graph.ainvoke({"task": task})


def run_sync(task: str, cfg: SwarmConfig) -> dict[str, Any]:
    return asyncio.run(run(task, cfg))
