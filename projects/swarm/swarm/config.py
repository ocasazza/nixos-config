"""Runtime configuration pulled from env with sensible defaults for luna."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class SwarmConfig:
    llm_base_url: str
    llm_api_key: str
    coder_model: str
    vision_model: str | None
    phoenix_endpoint: str
    max_parallel_agents: int
    default_fanout: int
    vault_root: Path
    obsidian_mcp_command: list[str] = field(default_factory=list)
    obsidian_mcp_env: dict[str, str] = field(default_factory=dict)


def load() -> SwarmConfig:
    vault_root = Path(
        os.environ.get("SWARM_VAULT_ROOT", str(Path.home() / "obsidian" / "vault"))
    ).expanduser()

    # Default to bootstrapping the MCP server via npx. We use
    # `@bitbonsai/mcpvault` — a direct-filesystem Obsidian MCP server
    # that reads vault files on disk (no Obsidian desktop / Local REST
    # API plugin required). The vault path is a POSITIONAL argument,
    # not an env var.
    #
    # Override with SWARM_OBSIDIAN_MCP_COMMAND (space-separated) to
    # point at a `npm -g` install or a from-source build. Whatever you
    # pass here must accept the vault path as its final positional
    # argument (we append it below), or set
    # SWARM_OBSIDIAN_MCP_APPEND_VAULT=0 to disable the append.
    mcp_cmd_raw = os.environ.get(
        "SWARM_OBSIDIAN_MCP_COMMAND",
        "npx -y @bitbonsai/mcpvault@latest",
    )
    obsidian_mcp_command = mcp_cmd_raw.split()
    if os.environ.get("SWARM_OBSIDIAN_MCP_APPEND_VAULT", "1") != "0":
        obsidian_mcp_command = [*obsidian_mcp_command, str(vault_root)]

    # `@bitbonsai/mcpvault` takes its configuration via positional args
    # (the vault path). It does not use env vars — so we keep this dict
    # empty by default. Callers can still inject env via
    # SwarmConfig-level overrides if a future server grows env needs.
    obsidian_mcp_env: dict[str, str] = {}

    return SwarmConfig(
        llm_base_url=os.environ.get("SWARM_LLM_BASE_URL", "http://localhost:4000/v1"),
        llm_api_key=os.environ.get("SWARM_LLM_API_KEY", "sk-swarm-local"),
        # These are LiteLLM model-group names (see litellm_config.yaml),
        # not raw HF ids — LiteLLM resolves them to a concrete backend.
        coder_model=os.environ.get("SWARM_CODER_MODEL", "coder"),
        # None until a vision-capable backend joins the swarm. browser-use
        # falls back to DOM-only mode when this is unset.
        vision_model=os.environ.get("SWARM_VISION_MODEL") or None,
        phoenix_endpoint=os.environ.get(
            "PHOENIX_COLLECTOR_ENDPOINT", "http://localhost:6006/v1/traces"
        ),
        # Hard cap on concurrent subagents. The vLLM coder pool can
        # saturate around 32 parallel requests on luna's 3090 Ti + RTX
        # 4000 before queueing dominates; exo adds more headroom.
        max_parallel_agents=int(os.environ.get("SWARM_MAX_PARALLEL", "32")),
        # How many workers the planner fans out to by default when it
        # doesn't specify its own count.
        default_fanout=int(os.environ.get("SWARM_DEFAULT_FANOUT", "8")),
        # Obsidian vault location on disk — passed as a positional arg
        # to the direct-fs MCP server.
        vault_root=vault_root,
        obsidian_mcp_command=obsidian_mcp_command,
        obsidian_mcp_env=obsidian_mcp_env,
    )
