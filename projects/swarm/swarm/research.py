"""Deep-research pipeline — a multi-stage graph that exercises the full
swarm stack end-to-end:

    START
      │
      ▼
    plan            (coder-local)      decompose question into claims
      │
      ▼
    route           (conditional)      skip if no claims; else fan out
      │
      ▼
    ┌── Send per-claim ─────────────────────────────────────────────┐
    │ retrieve     (vault | browser | reason)                       │
    │ distill      (coder-remote, parallel — per-claim synthesis)   │
    └─── collect via Annotated reducer ─────────────────────────────┘
      │
      ▼
    cross_ref       (coder-local)      reconcile conflicts / agree
      │
      ▼
    critique        (coder-remote)     adversarial challenge pass
      │
      ▼
    refine          (coder-local)      revise based on critique
      │
      ▼
    final           (coder-local)      cited synthesis
      │
      ▼
    END

Rationale for the local / remote split:

    latency-sensitive + single-shot → coder-local (plan / cross_ref /
      refine / final)
    fan-out heavy + critique / enrichment → coder-remote (distill /
      critique), which routes across exo / GFR federation

Each claim's retrieve step chooses a tool based on the claim's `source`
hint from the planner:
    "vault"  → read-only Obsidian vault via MCP (via agents.vault)
    "web"    → browser-use Playwright subagent (via agents.browser)
    "reason" → no tool, coder-local pure-text reasoning
"""

from __future__ import annotations

import asyncio
import json
import os
from typing import Annotated, Any, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.constants import Send
from langgraph.graph import END, START, StateGraph

from swarm import telemetry
from swarm.agents.browser import run_browser_task
from swarm.agents.vault import run_vault_task
from swarm.config import SwarmConfig, load


def _reduce_list(left: list[Any], right: list[Any]) -> list[Any]:
    """Concatenating reducer so parallel per-claim workers append freely."""
    return (left or []) + (right or [])


class ResearchState(TypedDict, total=False):
    question: str
    claims: list[dict[str, Any]]
    findings: Annotated[list[dict[str, Any]], _reduce_list]
    synthesis: str
    critique: str
    refined: str
    answer: str


class ClaimState(TypedDict):
    question: str
    claim: dict[str, Any]


# ── Prompts ────────────────────────────────────────────────────────────

PLAN_SYSTEM = """You are the planner of a deep-research pipeline.

The user asks a question. Decompose it into 3–6 INDEPENDENT, FALSIFIABLE
claims — each one a concrete sub-question that can be investigated on its
own. For every claim, pick a `source`:

  "vault"  — the user's Obsidian knowledge base (their notes / journal /
             prompt library). Pick this when the claim likely lives in
             their own writing.
  "web"    — live web browsing. Pick this for fresh facts, current
             events, or vendor docs.
  "reason" — pure text reasoning; no external source. Pick this for
             purely analytical or conceptual sub-questions.

Return STRICT JSON, nothing else:

{{
  "claims": [
    {{"id": "c1", "source": "vault" | "web" | "reason",
      "question": "short, concrete sub-question"}},
    ...
  ]
}}

Hard cap: {max_claims} claims.
"""

DISTILL_SYSTEM = """You evaluate ONE piece of retrieved evidence against
ONE research claim. Your job is to produce a short critical summary:

  - Restate the claim in one line.
  - Summarize what the evidence DOES support (quote / cite specifics).
  - Flag what the evidence DOES NOT support, or where it's ambiguous.
  - Rate confidence: "high" | "medium" | "low".

Be blunt. 4–8 sentences. No bullet lists. No headings."""

CROSS_REF_SYSTEM = """You are the cross-reference step of a research
pipeline. You receive the original question and a list of per-claim
findings (each with confidence + evidence summary). Produce a short
synthesis that:

  - Identifies AGREEMENTS across claims (where findings reinforce each
    other).
  - Identifies CONFLICTS across claims (where findings contradict or
    cast doubt on each other).
  - Flags GAPS — things the question asks about that no claim covered.

4–8 sentences of prose. No headings. No bullets."""

CRITIQUE_SYSTEM = """You are the adversarial critic of a research
pipeline. You receive the original question and the current synthesis.
Your job is to attack the synthesis:

  - What's the strongest counter-argument?
  - What load-bearing assumption is weakest?
  - What evidence is being over-generalized?
  - What's the biggest missing consideration?

Be specific and concrete — quote the synthesis where you're attacking
it. 4–8 sentences. No lists."""

REFINE_SYSTEM = """You are the refinement step of a research pipeline.
You receive:
    - the original question
    - the current synthesis
    - an adversarial critique

Produce a revised synthesis that incorporates the critique's valid
points, explicitly concedes where the critique has a point, and
strengthens the reasoning where it doesn't. Do NOT write a response to
the critique — just ship the improved synthesis as prose.
4–10 sentences."""

FINAL_SYSTEM = """You are the final writer of a research pipeline. You
receive:
    - the original question
    - a refined synthesis
    - the full list of per-claim findings (with ids)

Produce a complete, cited answer to the original question:
    - Open with a one-paragraph direct answer.
    - Follow with 1-3 paragraphs of reasoning.
    - Cite claim ids inline where a claim's finding supports a point,
      e.g. "... (c2)".
    - Close with one sentence flagging any remaining uncertainty.

Plain prose. Markdown allowed but no headings."""

# ── Graph construction ────────────────────────────────────────────────


def build_research_graph(cfg: SwarmConfig):
    # Local = always-on anchor. Remote = fan-out / critique pool.
    # `coder-local` / `coder-remote` are LiteLLM group names, NOT raw
    # HF ids — see projects/swarm/litellm_config.yaml.
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
        temperature=0.4,
    )

    async def plan(state: ResearchState) -> ResearchState:
        max_claims = min(cfg.default_fanout, 6)
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=PLAN_SYSTEM.format(max_claims=max_claims)),
                HumanMessage(content=state["question"]),
            ]
        )
        claims = _parse_claims(msg.content, cap=max_claims)
        return {"claims": claims}

    async def investigate(state: ClaimState) -> ResearchState:
        """Per-claim node: retrieve evidence, then distill it on remote.

        The two substeps happen in the same node rather than as separate
        graph nodes so each claim's retrieve+distill pair is a single
        parallel unit of work — fewer Send hops, simpler state.
        """
        claim = state["claim"]
        claim_id = claim.get("id", "?")
        source = claim.get("source", "reason")
        question = claim.get("question", "")

        if source == "vault":
            evidence = await run_vault_task(question, cfg)
        elif source == "web":
            evidence = await run_browser_task(question, cfg)
        else:
            reasoning = await local_llm.ainvoke([HumanMessage(content=question)])
            evidence = reasoning.content

        # Distill on remote so the fan-out load hits the coder-remote
        # pool (exo / GFR) instead of luna's single vLLM.
        distill_prompt = (
            f"Claim: {question}\n\n"
            f"Evidence (from source={source}):\n{_truncate(evidence, 6000)}"
        )
        distilled = await remote_llm.ainvoke(
            [
                SystemMessage(content=DISTILL_SYSTEM),
                HumanMessage(content=distill_prompt),
            ]
        )

        return {
            "findings": [
                {
                    "id": claim_id,
                    "source": source,
                    "question": question,
                    "evidence": _truncate(evidence, 4000),
                    "distilled": distilled.content,
                }
            ]
        }

    async def cross_ref(state: ResearchState) -> ResearchState:
        bundle = json.dumps(state.get("findings", []), indent=2, default=str)
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=CROSS_REF_SYSTEM),
                HumanMessage(
                    content=f"Original question:\n{state['question']}\n\n"
                    f"Findings:\n{_truncate(bundle, 16000)}"
                ),
            ]
        )
        return {"synthesis": msg.content}

    async def critique(state: ResearchState) -> ResearchState:
        msg = await remote_llm.ainvoke(
            [
                SystemMessage(content=CRITIQUE_SYSTEM),
                HumanMessage(
                    content=f"Original question:\n{state['question']}\n\n"
                    f"Synthesis:\n{state.get('synthesis', '')}"
                ),
            ]
        )
        return {"critique": msg.content}

    async def refine(state: ResearchState) -> ResearchState:
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=REFINE_SYSTEM),
                HumanMessage(
                    content=(
                        f"Original question:\n{state['question']}\n\n"
                        f"Synthesis:\n{state.get('synthesis', '')}\n\n"
                        f"Critique:\n{state.get('critique', '')}"
                    )
                ),
            ]
        )
        return {"refined": msg.content}

    async def final(state: ResearchState) -> ResearchState:
        # Trim each finding before serializing — the browser agent
        # especially can dump tens of thousands of tokens into `evidence`
        # and we don't want one chatty claim to blow the final prompt.
        trimmed = [
            {**f, "evidence": _truncate(f.get("evidence", ""), 2000)}
            for f in state.get("findings", [])
        ]
        bundle = json.dumps(trimmed, indent=2, default=str)
        msg = await local_llm.ainvoke(
            [
                SystemMessage(content=FINAL_SYSTEM),
                HumanMessage(
                    content=(
                        f"Original question:\n{state['question']}\n\n"
                        f"Refined synthesis:\n{state.get('refined', '')}\n\n"
                        f"Findings:\n{_truncate(bundle, 14000)}"
                    )
                ),
            ]
        )
        return {"answer": msg.content}

    def route_after_plan(state: ResearchState) -> list[Send] | Literal["__end__"]:
        claims = state.get("claims") or []
        if not claims:
            return END  # type: ignore[return-value]
        return [
            Send("investigate", {"question": state["question"], "claim": c})
            for c in claims
        ]

    graph = StateGraph(ResearchState)
    graph.add_node("plan", plan)
    graph.add_node("investigate", investigate)
    graph.add_node("cross_ref", cross_ref)
    graph.add_node("critique", critique)
    graph.add_node("refine", refine)
    graph.add_node("final", final)

    graph.add_edge(START, "plan")
    graph.add_conditional_edges("plan", route_after_plan, ["investigate", END])
    graph.add_edge("investigate", "cross_ref")
    graph.add_edge("cross_ref", "critique")
    graph.add_edge("critique", "refine")
    graph.add_edge("refine", "final")
    graph.add_edge("final", END)

    return graph.compile().with_config({"max_concurrency": cfg.max_parallel_agents})


# ── Helpers ───────────────────────────────────────────────────────────


def _truncate(value: Any, limit: int) -> str:
    s = value if isinstance(value, str) else str(value)
    if len(s) <= limit:
        return s
    return s[:limit] + f"\n...[truncated {len(s) - limit} chars]"


def _parse_claims(raw: str | list, cap: int) -> list[dict[str, Any]]:
    """Tolerate JSON wrapped in markdown fences — smaller models emit
    ```json ... ``` even when asked for bare JSON."""
    text = (
        raw
        if isinstance(raw, str)
        else "".join(
            part.get("text", "") if isinstance(part, dict) else str(part)
            for part in raw
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
        return [{"id": "c1", "source": "reason", "question": text[:2000]}]
    claims = obj.get("claims") if isinstance(obj, dict) else obj
    if not isinstance(claims, list):
        return []
    out: list[dict[str, Any]] = []
    for idx, c in enumerate(claims[:cap]):
        if not isinstance(c, dict):
            continue
        source = c.get("source", "reason")
        if source not in {"vault", "web", "reason"}:
            source = "reason"
        out.append(
            {
                "id": str(c.get("id") or f"c{idx + 1}"),
                "source": source,
                "question": str(c.get("question", "")).strip(),
            }
        )
    return [c for c in out if c["question"]]


# ── Entry points ──────────────────────────────────────────────────────


def make_graph():
    """Factory called by `langgraph dev` for each run."""
    cfg = load()
    telemetry.init(
        cfg.phoenix_endpoint,
        service_name=os.environ.get("OTEL_SERVICE_NAME", "swarm-research"),
    )
    return build_research_graph(cfg)


async def run(question: str, cfg: SwarmConfig) -> dict[str, Any]:
    graph = build_research_graph(cfg)
    return await graph.ainvoke({"question": question})


def run_sync(question: str, cfg: SwarmConfig) -> dict[str, Any]:
    return asyncio.run(run(question, cfg))
