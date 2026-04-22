"""Browser subagent. Wraps `browser-use` so it plugs into LangGraph.

Runs in DOM/text mode when no vision model is configured — the coder
model sees element trees and accessibility labels rather than raw pixels.
This is enough for BrowseComp-style tasks on most sites; enable a vision
backend (Qwen2.5-VL via a worker node) for visually-heavy pages.
"""

from __future__ import annotations

from ..config import SwarmConfig


async def run_browser_task(
    instruction: str,
    cfg: SwarmConfig,
    max_steps: int = 25,
) -> str:
    """Drive a headless Chromium to complete `instruction`, return final text.

    Imported lazily so `swarm --help` doesn't pay the playwright import
    cost. browser-use ships its own OpenAI-compatible ChatOpenAI (it
    can't monkey-patch LangChain's because LangChain uses pydantic
    models with `extra: forbid`); we use the native one and point it at
    the LiteLLM proxy.
    """
    from browser_use import Agent, ChatOpenAI

    llm = ChatOpenAI(
        model=cfg.coder_model,
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.1,
    )

    agent = Agent(
        task=instruction,
        llm=llm,
        # Force DOM-mode when no vision model is wired up. browser-use
        # auto-detects vision capability on newer releases; this flag
        # is harmless (ignored) if the version doesn't support it.
        use_vision=cfg.vision_model is not None,
    )
    history = await agent.run(max_steps=max_steps)

    # IMPORTANT: never return `str(history)` — that serializes the full
    # AgentHistoryList including every interacted DOM element, CSS
    # selector, screenshot placeholder, and long_term_memory entry per
    # step. A single 25-step run can emit ~40k tokens of noise, which
    # then blows up the reducer's prompt past vLLM's 32k max_model_len.
    # The agent's `done` action text is the only thing the reducer
    # actually needs; fall back to a concatenation of the non-empty
    # extracted_content entries (also short), and finally a terse stub.
    final = history.final_result()
    if final:
        return final
    extracted = [c for c in history.extracted_content() if c]
    if extracted:
        # Cap to something sane so a pathological run can't leak bloat
        # back in via the fallback path.
        joined = "\n".join(extracted)
        return joined[:8000]
    return f"(browser agent finished with no final result; done={history.is_done()})"
