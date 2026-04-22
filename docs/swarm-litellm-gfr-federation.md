# LiteLLM `coder` federation: local vLLM + local-tunnelled exo + GFR exo

This note tracks how luna's LiteLLM proxy (`projects/swarm/litellm_config.yaml`,
bound to the 10G NIC, see `systems/x86_64-linux/luna/default.nix`)
fans the `coder-local` / `coder-remote` model groups out over **four** backends:

1. **Local vLLM** (`http://localhost:8000/v1`) — primary, `weight: 10`.
   Qwen3-Coder-30B AWQ, tensor-parallel across both luna GPUs. Module:
   `modules/nixos/vllm/`.
2. **Local exo tunnel** (`http://localhost:52416/v1`) — legacy overflow,
   `weight: 1`. SSH local-forward to `gfr-osx26-03:52415` via the GFR-side
   `.just/runners.just` targets. Works only while the tunnel is up.
3. **GFR exo node 02** (`https://gfr-proxy.schrodinger.com/exo/02/v1`)
   — `weight: 1`, Bearer-authenticated. Endpoint URL is a **placeholder**
   until the GFR-side reverse proxy lands (see design spec below).
4. **GFR exo node 03** (`https://gfr-proxy.schrodinger.com/exo/03/v1`)
   — same shape as node 02.

## Auth-token flow

```
secrets/gfr-exo-auth-token.yaml        (sops-encrypted, this repo)
  ├── admin key: age13qgz…                     (human edit)
  └── host key : age1jxcq…  (luna ssh host)    (activation decrypt)
                        │
                        ▼
/run/secrets/gfr-exo-auth-token        (sops-nix drops at activation)
                        │
                        ▼
export GFR_EXO_AUTH_TOKEN="$(sudo cat /run/secrets/gfr-exo-auth-token)"
                        │
                        ▼
litellm (reads from env as per `api_key: os.environ/GFR_EXO_AUTH_TOKEN`)
                        │  Authorization: Bearer <token>
                        ▼
https://gfr-proxy.schrodinger.com/exo/<node>/v1/chat/completions
                        │  (TB5 mesh hop on the GFR side)
                        ▼
http://10.200.0.{12,13}:52415/v1/chat/completions   (real exo API)
```

## Known gaps

- **GFR-side proxy is not deployed yet.** Endpoint URLs above are
  fabricated placeholders. See
  [`design/gfr-exo-auth-proxy.md`](design/gfr-exo-auth-proxy.md) for the
  proposed architecture; it needs to land in the GFR repo
  (`schrodinger/git-fleet-runner`) separately.
- **Token ciphertext ships with `REPLACE_ME_WITH_REAL_TOKEN`.** Real
  value drops in via
  `sops edit secrets/gfr-exo-auth-token.yaml` from a machine holding the
  admin age key, once the GFR-side proxy is up and can mint a value.
- **LiteLLM is still bash-launched, not systemd.** The env-var export
  above has to happen in the user's shell before `scripts/start-litellm.sh`.
  Promoting LiteLLM to `modules/nixos/litellm/` with an
  `EnvironmentFile=/run/secrets/gfr-exo-auth-token` would make this
  fully declarative. Tracked as a follow-up; not blocking.

## Health-check & cooldown behaviour

LiteLLM's router already quarantines a deployment after
`allowed_fails: 1` for `cooldown_time: 60s`. That's sufficient for the
GFR endpoints going dark — clients see the `coder` model group stay
healthy on local vLLM while the remote exo cluster is offline or the
proxy is failing auth.
