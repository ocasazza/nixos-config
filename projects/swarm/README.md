# Swarm

LangGraph-based multi-agent swarm over LiteLLM. Local replacement for the
marketing promises of the `kimi-2-6/kimi-2.6` repo, built from trusted
open-source parts:

| Layer         | Component                            |
| ------------- | ------------------------------------ |
| Orchestration | **LangGraph** (planner → fan-out → reducer) |
| Model router  | **LiteLLM** proxy on `:4000`         |
| Backends      | local **vLLM** (`:8000`), **exo** (`:52416`), future worker nodes |
| Browser       | **browser-use** + Playwright         |
| Visualization | **Arize Phoenix** (`:6006`)          |

## Boot

```sh
# From the nixos-config repo root
nix develop
cd projects/swarm
uv sync
uv run playwright install chromium

# Brings up Phoenix + LiteLLM. vLLM is already a systemd unit.
./scripts/start-swarm.sh
```

Open <http://localhost:6006> to watch the live trace tree.

## Use

```sh
uv run swarm run "Find the top 3 Hacker News posts right now and summarize each."
uv run swarm config
```

## Adding backends

Edit `litellm_config.yaml`, add another `- model_name: coder-local`
or `- model_name: coder-remote` block with the new host's `api_base`,
and restart the proxy. LiteLLM's health checks skip dead endpoints
automatically, so exo / worker nodes can come and go without touching
the LangGraph code.

## Adding a worker node

On a new NixOS host, enable `local.vllm` with the same model:

```nix
local.vllm = {
  enable = true;
  openFirewall = true;
  services.coder = {
    model = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ";
    port = 8000;
    gpuMemoryUtilization = 0.85;
    maxModelLen = 32768;
  };
};
```

Then add `http://<hostname>.local:8000/v1` to `litellm_config.yaml`.
