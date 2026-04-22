# GFR-side authenticated reverse proxy for exo (design spec)

**Status:** proposed. This spec lives in `nixos-config` so it ships with
the luna-side consumer (`secrets/gfr-exo-auth-token.yaml` +
`projects/swarm/litellm_config.yaml`), but the implementation belongs in
`schrodinger/git-fleet-runner`. Move/copy there when landing.

**Context source:** scout of `git-fleet-runner` on `main` and every
remote branch (`feat/exo`, `feat/shared-seaweedfs-flake`,
`fix/code-signing-activation`, `main`) as of 2026-04-21. No existing
reverse proxy, bearer-auth layer, stunnel, caddy config, traefik config,
or token-gated surface in front of exo was found. Only tokens in-repo
are GitHub PAT registration tokens (`shared.yaml::git-fleet/token`,
`git-fleet-runner/token`). Exo currently runs on
`10.200.0.12:52415` / `10.200.0.13:52415` (TB5 mesh plane), and
`nix/systems/aarch64-darwin/gfr-osx26-0{2,3}/default.nix` explicitly
PF-blocks `:52415` on non-mesh interfaces. The only user-facing path is
the SSH local-forward wrappers in `.just/runners.just` (exo-tunnel
targets).

## Problem

luna needs to reach exo on nodes 02/03 from **off the TB5 mesh** (home
LAN across the VPN / corp MITM). The mesh is point-to-point between the
three GFR hosts; luna is not a member and cannot be added without
redesigning the RDMA topology. SSH tunnels (the current escape hatch)
work but are:

- fragile — one tunnel per node, dies on network wobble
- tied to a human (`quark@<host>` key pair)
- unauthenticated at the application layer (whoever holds the SSH key
  is whoever exo serves)

We want a **stable, auth-gated, off-mesh endpoint** that LiteLLM on luna
can federate into the `coder` model group.

## Proposal

Run a TLS-terminating reverse proxy on **gfr-osx26-04** (the manager
node, already the Grafana + shared-secrets host). Node 04 has ethernet
to the corp network, doesn't participate in exo itself
(`exo.enable = false` — see `nix/systems/aarch64-darwin/gfr-osx26-04/default.nix`),
and has a reachable corp hostname.

### Endpoint shape

```
https://gfr-proxy.schrodinger.com/exo/<node>/v1/...
  Authorization: Bearer <GFR_EXO_AUTH_TOKEN>
      │
      ▼  (TLS → 04, strip Authorization, forward mesh)
http://10.200.0.12:52415/v1/...  (node 02)
http://10.200.0.13:52415/v1/...  (node 03)
```

Listens on **04's ethernet IP** only — PF keeps `:52415` blocked on
non-mesh, but the proxy is on `:443` (a different port), so the existing
PF rules don't need widening.

### Implementation choice: caddy

- One-file config (`Caddyfile`), zero ceremony around ACME, matches the
  existing `nix/modules/darwin/baseline/default.nix` pattern of running
  nginx as a proxy (the nix-cache Content-Encoding strip proxy). We can
  factor a reusable nginx module, but caddy's short declarative ACME on
  an internal domain is simpler for a fresh greenfield.
- Alternatives rejected: **nginx** needs its own TLS renewal plumbing
  (corp CA + internal ACME is nontrivial); **traefik** is overkill for
  two upstream routes and one auth check; **stunnel** doesn't do path-
  based routing to two nodes.

### New files (inside `git-fleet-runner`)

```
nix/modules/darwin/exo-auth-proxy/default.nix
secrets/gfr-osx26-04.yaml                 (add: exo-auth/token)
.sops.yaml                                (ship a rule for the above)
```

### Module shape (`services.exo-auth-proxy`)

```nix
{ config, lib, pkgs, ... }:

let cfg = config.services.exo-auth-proxy; in {
  options.services.exo-auth-proxy = {
    enable = lib.mkEnableOption "caddy reverse proxy in front of exo nodes";
    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname clients use (Caddy TLS cert SAN).";
      example = "gfr-proxy.schrodinger.com";
    };
    listenAddr = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address on 04. Ethernet IP recommended.";
    };
    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the Bearer token (no trailing newline).
        Consumers (e.g. luna's LiteLLM) must present this value in an
        Authorization header. Typically sops-provisioned as
        config.sops.secrets."exo-auth/token".path.
      '';
    };
    nodes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          meshIP = lib.mkOption { type = lib.types.str; };
          meshPort = lib.mkOption { type = lib.types.int; default = 52415; };
        };
      });
      description = ''
        Map of node-label → mesh-facing exo endpoint. Each label becomes
        a path segment (e.g. "02" → /exo/02/v1/...).
      '';
      example = lib.literalExpression ''
        {
          "02" = { meshIP = "10.200.0.12"; };
          "03" = { meshIP = "10.200.0.13"; };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      # Caddyfile rendered with the token loaded from tokenFile at
      # activation. The header_up strip removes the client's bearer
      # before forwarding so exo never sees the secret.
      globalConfig = "auto_https on";
      virtualHosts.${cfg.hostname} = {
        listenAddresses = [ cfg.listenAddr ];
        extraConfig = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (label: node: ''
            handle_path /exo/${label}/* {
              @authed header Authorization "Bearer {file.${cfg.tokenFile}}"
              handle @authed {
                reverse_proxy http://${node.meshIP}:${toString node.meshPort} {
                  header_up -Authorization
                }
              }
              respond 401
            }
          '') cfg.nodes
        );
      };
    };

    # Open corp-facing 443; 52415 stays blocked by existing PF rules.
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
```

### Host wiring (`nix/systems/aarch64-darwin/gfr-osx26-04/default.nix`)

```nix
sops.secrets."exo-auth/token" = {
  sopsFile = ../../../secrets/gfr-osx26-04.yaml;
  key = "exo-auth/token";
  owner = "caddy";
  mode = "0400";
};

services.exo-auth-proxy = {
  enable = true;
  hostname = "gfr-proxy.schrodinger.com";
  listenAddr = "<04-ethernet-IP>";
  tokenFile = config.sops.secrets."exo-auth/token".path;
  nodes = {
    "02".meshIP = "10.200.0.12";
    "03".meshIP = "10.200.0.13";
  };
};
```

### Token provisioning

1. On 04, generate once: `openssl rand -hex 32 | sops encrypt --input-type
binary --output-type yaml /dev/stdin > …`, stash as
   `secrets/gfr-osx26-04.yaml::exo-auth/token`. Encrypt to both the admin
   age key and 04's host age key (see existing `shared.yaml` for the
   pattern).
2. Share out-of-band to luna's operator, who then `sops edit
secrets/gfr-exo-auth-token.yaml` in `nixos-config` and pastes the
   same value. Both sides match; federation works.
3. Rotation: regenerate on 04, update luna's ciphertext, `sops
updatekeys`, rebuild both ends. The LiteLLM proxy picks up the new
   value on restart since it reads via `os.environ/GFR_EXO_AUTH_TOKEN`.

### Observability

- Add a Prometheus scrape job in `services.fleet-manager.observability`
  for the caddy admin endpoint (`:2019/metrics`). Useful panels: request
  rate by node, 401 rate (failed-auth probe attempts), upstream latency.
- Log failed-auth responses into loki so brute-force attempts stand out.

### Known limitations / non-goals

- **Not HA.** 04 is a single point of failure. If 04 is down, luna
  drops the GFR exo backends but keeps local vLLM + SSH-tunnelled exo.
  LiteLLM's `cooldown_time` handles the flapping transparently.
- **Single-token model.** One shared bearer for both nodes; no per-
  client revocation. That's acceptable for a two-party federation
  (luna + GFR manager) but wouldn't scale to per-user.
- **No rate-limiting at the proxy.** Rely on exo's own queue backpressure
  and LiteLLM's retry budget. If abuse becomes a concern, add
  `rate_limit` to the caddy matcher.

## Acceptance checks

- From luna, `curl -H 'Authorization: Bearer <wrong>' …/exo/02/v1/models`
  → `401`.
- With the right token → 200 + exo's model list.
- LiteLLM's `/v1/chat/completions?model=coder` with vLLM paused routes
  through to GFR exo, streams tokens, and the OTEL trace in Phoenix
  shows the remote upstream span.
- `nix eval .#darwinConfigurations.gfr-osx26-04.config.system.build.toplevel.drvPath`
  succeeds on the GFR repo.
