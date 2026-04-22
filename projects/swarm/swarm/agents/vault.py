"""Obsidian-vault subagent. Talks to an MCP server over stdio and exposes
its tools to a small LangChain tool-calling agent.

MCP server command (settled during integration):

    npx -y @bitbonsai/mcpvault@latest <vault-path>

We use `@bitbonsai/mcpvault` — a direct-filesystem Obsidian MCP server
that reads vault files straight from disk (no Obsidian desktop app or
Local REST API plugin required). This is the right shape for luna,
which is a headless GPU host.

The vault path is passed as a positional argument, not an env var.
See `swarm.config.SwarmConfig.obsidian_mcp_command`.

This agent is read-only v1 — we filter the tool list to a pure-read
subset before handing it to the LLM so the agent physically cannot
write, patch, move, or delete even if the planner asks it to.
"""

from __future__ import annotations

import os
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from ..config import SwarmConfig

# Tools exposed by @bitbonsai/mcpvault that do NOT mutate the vault.
# The server also exposes write_note / patch_note / delete_note /
# move_note / move_file / update_frontmatter / manage_tags — those are
# deliberately excluded here so the LLM physically cannot call them.
_READ_ONLY_TOOLS = frozenset(
    {
        "read_note",
        "read_multiple_notes",
        "list_directory",
        "list_all_tags",
        "search_notes",
        "get_frontmatter",
        "get_notes_info",
        "get_vault_stats",
    }
)

VAULT_SYSTEM = """You are the Obsidian-vault subagent of a parallel agent swarm.

You have read-only access to the user's Obsidian vault via MCP tools.
Use the tools to search, list, and read notes. You MUST NOT attempt to
write, patch, rename, or delete anything — no such tools are exposed to
you. When you have enough information, answer the instruction concisely
in plain Markdown and stop calling tools.

Vault root (on disk, for reference when the tools return relative paths):
{vault_root}
"""


async def run_vault_task(instruction: str, cfg: SwarmConfig) -> str:
    """Answer `instruction` by driving an MCP-backed Obsidian agent.

    Spawns the MCP server as a stdio subprocess per invocation (the adapter
    starts a fresh session for each tool call anyway), loads the exposed
    tools, filters them to the read-only subset, and runs a LangGraph
    react agent until the model stops calling tools.
    """
    # Imported lazily so `swarm --help` and non-vault subtasks don't pay
    # the MCP / langgraph.prebuilt import cost.
    from langchain_mcp_adapters.client import MultiServerMCPClient
    from langgraph.prebuilt import create_react_agent

    # Merge the server env with the current process env so the spawned
    # node process inherits PATH etc. but cfg-provided values win.
    env = {**os.environ, **(cfg.obsidian_mcp_env or {})}

    command, *args = cfg.obsidian_mcp_command
    client = MultiServerMCPClient(
        {
            "obsidian": {
                "transport": "stdio",
                "command": command,
                "args": args,
                "env": env,
            }
        }
    )

    all_tools = await client.get_tools(server_name="obsidian")
    tools = [t for t in all_tools if t.name in _READ_ONLY_TOOLS]
    if not tools:
        # Fail loudly rather than silently letting the LLM run without
        # tools — that would produce confidently wrong answers.
        exposed = ", ".join(sorted(t.name for t in all_tools)) or "(none)"
        raise RuntimeError(
            "Obsidian MCP server exposed no read-only tools we recognise. "
            f"Got: {exposed}. Expected at least one of: "
            f"{', '.join(sorted(_READ_ONLY_TOOLS))}"
        )

    llm = ChatOpenAI(
        model=cfg.coder_model,
        base_url=cfg.llm_base_url,
        api_key=cfg.llm_api_key,
        temperature=0.2,
    )

    agent = create_react_agent(llm, tools)
    result: dict[str, Any] = await agent.ainvoke(
        {
            "messages": [
                SystemMessage(content=VAULT_SYSTEM.format(vault_root=cfg.vault_root)),
                HumanMessage(content=instruction),
            ]
        }
    )

    messages = result.get("messages", [])
    if not messages:
        return ""
    final = messages[-1]
    content = getattr(final, "content", final)
    if isinstance(content, str):
        return content
    # AIMessage content can be a list of content-parts; join any text bits.
    return "".join(
        part.get("text", "") if isinstance(part, dict) else str(part)
        for part in (content if isinstance(content, list) else [content])
    )
