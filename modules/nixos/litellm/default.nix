# LiteLLM proxy as a systemd service.
#
# LiteLLM (https://docs.litellm.ai/) is an OpenAI-compatible federator:
# one HTTP surface in front of many upstream model backends (vLLM, exo,
# hosted OpenAI, hosted Anthropic, etc.). luna uses it as the unified
# endpoint for every AI client (claude-code, opencode, hermes) in front
# of local vLLM (:8000, :8002), the exo / GFR-exo federation, and the
# vertex-proxy passthrough for Anthropic/GCP — exposed at :4000.
#
# Packaging approach (mirrors `modules/nixos/vllm/default.nix` and
# `modules/nixos/mcpo/default.nix`):
#   * `litellm[proxy]` ships on PyPI. We install it into a uv-managed
#     venv at first service start, pinned by `cfg.litellmVersion`. The
#     venv is version-stamped and auto-recreated on version bumps.
#   * Master key (bearer token internal clients present to the proxy)
#     is loaded at unit start via `EnvironmentFile` from a sops-decrypted
#     file, NOT baked into the YAML config.
#   * Per-client virtual keys (external clients: claude-code, opencode,
#     hermes) are ADDITIVE EnvironmentFiles. Each sops secret contains
#     a single `LITELLM_API_KEY_<CLIENT>=sk-...` line that surfaces in
#     the proxy's env; the key provisioning is done post-boot via the
#     LiteLLM `/key/generate` API.
#
# Parameterization philosophy: every endpoint/model-group/auth path is
# an option with a sensible default. Host configs override only what
# they care about. The module body should never mention concrete URLs,
# model IDs, or secret paths.
#
# Usage:
#   local.litellm = {
#     enable = true;
#     endpoint = "http://luna:4000";    # clients reference this
#     modelGroups = { coder-local = [ ... ]; coder-cloud-claude = [ ... ]; };
#     passthroughEndpoints.vertex = { path = "/vertex"; target = "..."; };
#     virtualKeys.opencode = config.sops.secrets.litellm-key-opencode.path;
#     openFirewall = true;
#     masterKeyFile = config.sops.secrets.litellm-master-key.path;
#   };
#
# Verify (after switch):
#   curl http://luna.local:4000/v1/models \
#     -H "Authorization: Bearer $(sudo cat /run/secrets/litellm-master-key | cut -d= -f2-)"
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.litellm;

  # Build model_list entries from the parameterized `modelGroups` attrset.
  # Each group maps to >= 1 deployments; each deployment is rendered as
  # a `{ model_name, litellm_params }` record under `model_list`.
  renderedModelList = lib.concatLists (
    lib.mapAttrsToList (
      groupName: deployments:
      map (dep: {
        model_name = groupName;
        litellm_params = {
          model = builtins.head dep.models;
          api_base = dep.api_base;
          api_key = dep.api_key;
          max_tokens = dep.max_tokens;
          weight = dep.weight;
          timeout = dep.timeout;
        };
      }) deployments
    ) cfg.modelGroups
  );

  # Pass-through endpoints: one HTTP-shaped dict per entry under
  # `general_settings.pass_through_endpoints`. Client's Authorization
  # header flows through untouched when `forwardHeaders = true`.
  renderedPassthroughEndpoints = lib.mapAttrsToList (_name: ep: {
    path = ep.path;
    target = ep.target;
    forward_headers = ep.forwardHeaders;
  }) cfg.passthroughEndpoints;

  # The full rendered config structure. Emitted to YAML via `builtins.toJSON`
  # (LiteLLM reads both YAML and JSON; the json shape is a valid subset).
  renderedConfig = {
    model_list = renderedModelList;
    router_settings = {
      routing_strategy = cfg.routerSettings.routingStrategy;
      num_retries = cfg.routerSettings.numRetries;
      timeout = cfg.routerSettings.timeout;
      allowed_fails = cfg.routerSettings.allowedFails;
      cooldown_time = cfg.routerSettings.cooldownTime;
    };
    litellm_settings = {
      drop_params = true;
      set_verbose = false;
    }
    // lib.optionalAttrs cfg.metrics.otelCallbacks {
      success_callback = [ "otel" ];
      failure_callback = [ "otel" ];
    };
    environment_variables = {
      OTEL_SERVICE_NAME = "litellm";
    };
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
    }
    // lib.optionalAttrs (renderedPassthroughEndpoints != [ ]) {
      pass_through_endpoints = renderedPassthroughEndpoints;
    }
    // lib.optionalAttrs (cfg.databaseUrl != null) {
      database_url = cfg.databaseUrl;
      store_model_in_db = false;
    };
  };

  # Rendered YAML file — one nix-store derivation. Swapping a model or
  # endpoint = single host-config edit, no manual YAML churn.
  renderedConfigFile = pkgs.writeText "litellm-config.yaml" (builtins.toJSON renderedConfig);

  # Team/key manifest consumed by the `litellm-team-bootstrap` unit.
  # Isolates nix from runtime: the bootstrap script reads JSON, not
  # nix expressions. `sopsFile` is intentionally excluded — the sops
  # round-trip lives in a separate (follow-up) derivation so the
  # manifest stays admin-API-agnostic.
  teamManifest = {
    teams = lib.mapAttrs (_n: t: {
      inherit (t)
        description
        models
        tpm
        rpm
        maxBudget
        budgetDuration
        ;
    }) cfg.teams;
    keys = lib.mapAttrs (_n: k: {
      inherit (k) team keyAlias;
    }) cfg.clientKeys;
  };
  teamManifestFile = pkgs.writeText "litellm-team-manifest.json" (builtins.toJSON teamManifest);

  # Fallback when caller has not defined any modelGroups: use the legacy
  # `configFile` option (path). This keeps the pre-parameterization
  # callers working on the next rebuild without changes.
  effectiveConfigFile = if cfg.modelGroups != { } then renderedConfigFile else cfg.configFile;

  # Bootstrap a uv-managed venv at first start, pip-install pinned
  # litellm[proxy], stamp the version, then exec. Idempotent across
  # restarts; version drift triggers a full venv rebuild (same pattern
  # as vllm / mcpo).
  #
  # `setuptools` is kept in the install list for the same reason as
  # the vllm module: a few transitive deps (triton's JIT, some gRPC
  # code paths) lazy-import `setuptools` at runtime, and litellm
  # doesn't pull it in as a hard dep.
  startScript = pkgs.writeShellScript "litellm-start" ''
    set -eu

    VENV="${cfg.venvDir}"
    LITELLM_VERSION="${cfg.litellmVersion}"
    VERSION_STAMP="$VENV/.litellm-version"

    # Recreate venv if the requested litellm version differs from what's
    # stamped (or stamp file missing -> fresh bootstrap).
    if [ -x "$VENV/bin/python" ] && [ -f "$VERSION_STAMP" ]; then
      installed_version="$(cat "$VERSION_STAMP")"
      if [ "$installed_version" != "$LITELLM_VERSION" ]; then
        echo "litellm: version changed ($installed_version -> $LITELLM_VERSION), recreating venv"
        rm -rf "$VENV"
      fi
    fi

    if [ ! -x "$VENV/bin/python" ]; then
      echo "litellm: bootstrapping venv at $VENV"
      ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
    fi

    # uv pip install is a near-instant no-op when the version is already
    # satisfied, so run it unconditionally to pick up bumps.
    #
    # prisma + prisma_binaries are only needed when databaseUrl is set
    # (virtual-key SQLite/Postgres path). Always installing them keeps
    # the venv's shape identical between DB-on / DB-off configurations
    # — no re-bootstrap churn when the flag is flipped.
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
      --quiet \
      "litellm[proxy]==$LITELLM_VERSION" \
      "setuptools" \
      "prisma"

    # Prisma needs its binary engines fetched once into the venv on
    # first boot (and after litellm version bumps recreate the venv).
    # `prisma py fetch` is idempotent; safe to run on every start.
    if [ -n "''${DATABASE_URL:-}" ] || grep -q 'database_url' "${toString effectiveConfigFile}"; then
      "$VENV/bin/prisma" py fetch --python="$VENV/bin/python" 2>&1 || true
    fi

    echo "$LITELLM_VERSION" > "$VERSION_STAMP"

    exec "$VENV/bin/litellm" \
      --config "${toString effectiveConfigFile}" \
      --port "${toString cfg.port}" \
      --host "${cfg.host}"
  '';

  deploymentSubmodule = types.submodule {
    options = {
      models = mkOption {
        type = types.listOf types.str;
        description = ''
          LiteLLM-format model identifier(s) for this deployment. Most
          entries have exactly one model; if multiple are provided the
          first is used (multi-model-per-deployment is not rendered).
          Examples:
            - "openai/cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ"
            - "anthropic/claude-opus-4-7"
        '';
      };
      api_base = mkOption {
        type = types.str;
        description = "Upstream HTTP base URL for this deployment.";
      };
      api_key = mkOption {
        type = types.str;
        default = "placeholder";
        description = ''
          API key passed upstream. Use a literal, an `os.environ/VAR`
          reference (resolved by LiteLLM at config-load time), or the
          magic string `forwarded-per-request` for passthrough-style
          deployments where the client's own Authorization header is
          forwarded (the literal here keeps LiteLLM's client-construct
          step from erroring).
        '';
      };
      weight = mkOption {
        type = types.int;
        default = 1;
        description = "Router weight for simple-shuffle strategy.";
      };
      max_tokens = mkOption {
        type = types.int;
        default = 8192;
        description = "Deployment's max output tokens cap.";
      };
      timeout = mkOption {
        type = types.int;
        default = 120;
        description = "Per-request timeout in seconds.";
      };
    };
  };

  passthroughSubmodule = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = ''
          URL path prefix LiteLLM listens on (e.g. `/vertex`). Client
          requests to this prefix are forwarded to `target` verbatim.
        '';
      };
      target = mkOption {
        type = types.str;
        description = "Upstream URL prefix to forward requests to.";
      };
      forwardHeaders = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to forward the client's request headers (in particular
          Authorization) to the upstream. With `true`, LiteLLM adds no
          auth state of its own for this path — the client's bearer is
          what reaches the upstream.
        '';
      };
    };
  };

  metricsSubmodule = types.submodule {
    options = {
      otelEndpoint = mkOption {
        type = types.str;
        default = "http://localhost:6006/v1/traces";
        description = ''
          OTLP/HTTP traces endpoint LiteLLM's `otel` callbacks export
          to. Default points at Phoenix on loopback (standard swarm
          layout). Override if Phoenix / the collector runs elsewhere.
        '';
      };
      otelCallbacks = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable `otel` in the `success_callback` and
          `failure_callback` lists. Disabling this still lets
          `prometheusEnabled` handle the /metrics scrape path.
        '';
      };
      prometheusEnabled = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to advertise the LiteLLM /metrics Prometheus endpoint
          (no toggle on the proxy itself; this option exists so the
          observability module can react to it declaratively).
        '';
      };
    };
  };

  routerSettingsSubmodule = types.submodule {
    options = {
      routingStrategy = mkOption {
        type = types.str;
        default = "simple-shuffle";
        description = "LiteLLM router strategy.";
      };
      numRetries = mkOption {
        type = types.int;
        default = 2;
      };
      timeout = mkOption {
        type = types.int;
        default = 120;
      };
      allowedFails = mkOption {
        type = types.int;
        default = 1;
      };
      cooldownTime = mkOption {
        type = types.int;
        default = 60;
      };
    };
  };

  # Declarative team: attribute name -> team_alias on the LiteLLM side.
  # The `team_id` UUID is server-generated and discovered by the
  # bootstrap oneshot via `GET /team/list` (indexed by team_alias).
  teamSubmodule = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        default = "";
        description = "Free-form description, visible in the /ui team list.";
      };
      models = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Model-group names this team is allowed to call. Must be a
          subset of the keys of `config.local.litellm.modelGroups`.
          Asserted at eval time.
        '';
      };
      tpm = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Tokens per minute cap for the whole team. null = unbounded.";
      };
      rpm = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Requests per minute cap for the whole team. null = unbounded.";
      };
      maxBudget = mkOption {
        type = types.nullOr types.float;
        default = null;
        description = "Max team spend (USD) within `budgetDuration`. null = unbounded.";
      };
      budgetDuration = mkOption {
        type = types.str;
        default = "30d";
        description = ''
          Rolling window for `maxBudget`. LiteLLM duration string
          (e.g. `30d`, `24h`). Ignored if `maxBudget` is null.
        '';
      };
    };
  };

  # Declarative client key. Populated by client modules when their
  # `litellm.team` is set (see modules/nixos/claude-code), or by host
  # configs directly for clients whose modules don't run on the same
  # host as the proxy (e.g. darwin claude-code, opencode, hermes).
  clientKeySubmodule = types.submodule {
    options = {
      team = mkOption {
        type = types.str;
        description = "Name of a team declared under local.litellm.teams.";
      };
      keyAlias = mkOption {
        type = types.str;
        description = ''
          Stable handle for this client's key. Used as the idempotency
          key against `/key/generate` — rerunning the bootstrap with the
          same alias finds the existing key rather than minting a new
          one. Convention: `<client-name>` (matches the sops filename
          stem, e.g. `claude-code-nixos`).
        '';
      };
      sopsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional: sops YAML file to write the minted value back into
          (via `sops set`). When set, darwin hosts (which can't reach
          the LiteLLM admin API at activation time) receive the minted
          value via sops-nix at their next rebuild. On luna itself this
          is a strict superset of what /run/litellm-oci/keys/<client>
          already provides; setting it is optional for luna-only keys.
          NOTE: the writeback unit is a follow-up; for now sopsFile is
          informational-only and the operator manually runs
          `sops edit secrets/litellm-key-<client>.yaml` to copy minted
          values into the sops yaml.
        '';
      };
    };
  };
in
{
  options.local.litellm = {
    enable = mkEnableOption "LiteLLM proxy (OpenAI-compatible federator)";

    endpoint = mkOption {
      type = types.str;
      default = "http://luna:4000";
      description = ''
        URL clients (claude-code, opencode, hermes) use to reach this
        LiteLLM instance. Module bodies never hardcode the host/port —
        they reference `config.local.litellm.endpoint`. Override here
        to point clients at a different deployment (e.g. a remote
        proxy, Tailscale-exposed luna, etc.).
      '';
    };

    databaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "sqlite:////var/lib/litellm/keys.db";
      description = ''
        Backing store for LiteLLM virtual keys, user metadata, and
        per-key spend tracking. When null (default), virtual keys are
        disabled and clients must authenticate with the master key.
        Setting this to a SQLite or Postgres URL activates the
        `POST /key/generate`, `/user/*`, `/key/*` admin endpoints.

        `store_model_in_db` is forced to false — model_list stays
        static from nix config, DB is only for auth metadata.
      '';
    };

    modelGroups = mkOption {
      type = types.attrsOf (types.listOf deploymentSubmodule);
      default = { };
      example = lib.literalExpression ''
        {
          coder-local = [ {
            models   = [ "openai/cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ" ];
            api_base = "http://localhost:8000/v1";
            api_key  = "sk-vllm-luna";
            weight   = 10;
          } ];
          coder-cloud-claude = [ {
            models   = [ "anthropic/claude-opus-4-7" ];
            api_base = "https://vertex-proxy.sdgr.app/v1";
            api_key  = "forwarded-per-request";
          } ];
        }
      '';
      description = ''
        Model groups registered with the LiteLLM router. Map of
        `group-name -> list of deployments`. Each deployment fans out
        as a `{ model_name: <group>, litellm_params: {...} }` entry in
        the generated config, so multiple deployments under the same
        group get load-balanced per `routerSettings.routingStrategy`.

        When this is non-empty, the module renders a YAML config
        derivation and ignores `cfg.configFile`. When empty, the module
        falls back to `cfg.configFile` (legacy path).
      '';
    };

    passthroughEndpoints = mkOption {
      type = types.attrsOf passthroughSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          vertex = {
            path = "/vertex";
            target = "https://vertex-proxy.sdgr.app";
            forwardHeaders = true;
          };
        }
      '';
      description = ''
        HTTP pass-through endpoints rendered under
        `general_settings.pass_through_endpoints`. Client requests to
        `<endpoint>/<path>/...` are forwarded verbatim to the upstream
        at `<target>/...`. With `forwardHeaders = true` LiteLLM
        adds no auth state — the client's own Authorization header
        (e.g. a GCP id-token) reaches the upstream unchanged.
      '';
    };

    virtualKeys = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = lib.literalExpression ''
        {
          opencode = config.sops.secrets.litellm-key-opencode.path;
          hermes   = config.sops.secrets.litellm-key-hermes.path;
        }
      '';
      description = ''
        Per-client virtual keys. Map of `client-name -> sops-decrypted
        EnvironmentFile path`. Each referenced file must contain a
        single `KEY=VALUE` line (systemd EnvironmentFile format); the
        module adds every path to the unit's EnvironmentFile list so
        the decrypted values land in the proxy's env.

        Actual key provisioning is additive: post-boot, the operator
        runs LiteLLM's `POST /key/generate` (authenticated with the
        master key) once per client and writes the result back into
        the sops YAML. Placeholder values work for the first rebuild.
      '';
    };

    routerSettings = mkOption {
      type = routerSettingsSubmodule;
      default = { };
      description = ''
        LiteLLM router knobs (strategy, retries, cooldown). Defaults
        match the swarm layout (`simple-shuffle` + 60s cooldown for
        exo quarantine).
      '';
    };

    metrics = mkOption {
      type = metricsSubmodule;
      default = { };
      description = ''
        Observability knobs. `otelEndpoint` is plumbed into the unit
        environment so LiteLLM's `otel` callbacks export to the right
        Phoenix/OTLP target.
      '';
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Legacy-path fallback: explicit YAML file consumed when
        `modelGroups` is empty. New deployments should use
        `modelGroups` + `passthroughEndpoints` and leave this null.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "TCP port for the OpenAI-compatible API.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Defaults to all interfaces so LAN clients (other
        workstations, the exo cluster, etc.) can reach it. Use
        `127.0.0.1` for loopback-only access.
      '';
    };

    masterKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/litellm-master-key";
      description = ''
        Path to a sops-decrypted file holding the master key. The file
        must contain a single line of the form
        `LITELLM_MASTER_KEY=sk-...`; systemd loads it as
        `EnvironmentFile` so the value surfaces in the proxy process's
        environment without ever landing in /nix/store.

        The rendered config references
        `general_settings.master_key: os.environ/LITELLM_MASTER_KEY`
        so the env var is what's actually in effect.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — the
        proxy is authenticated via the master key or per-client
        virtual keys; only flip this on for LAN-trusted hosts.
      '';
    };

    phoenixEndpoint = mkOption {
      type = types.str;
      default = cfg.metrics.otelEndpoint;
      defaultText = lib.literalExpression "config.local.litellm.metrics.otelEndpoint";
      description = ''
        Deprecated: use `metrics.otelEndpoint` instead. Kept as a
        read-through alias so older host configs keep working.
      '';
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables exported to the LiteLLM process.
        Useful for feeding `os.environ/<NAME>` references in the YAML
        config (e.g. `GFR_EXO_AUTH_TOKEN` for the coder-remote pool).
      '';
    };

    # ── OCI container mode ─────────────────────────────────────────────
    # Alternative packaging that swaps the nix-native venv systemd unit
    # for an upstream OCI image plus a sidecar Postgres. The motivation
    # is the /ui admin route, which hard-requires Prisma's Rust query-
    # engine binary; upstream's `linux-nixos` build is not published on
    # `binaries.prisma.sh`, and `prisma-engines` in nixpkgs only ships
    # `schema-engine`. The `ghcr.io/berriai/litellm-database` image
    # bundles both engines and runs `prisma db push` at start, so the
    # UI works without any patching on our side. See the plan file
    # `~/.claude/plans/litellm-oci-container.md` for full context.
    useOciContainer = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Swap the nix-native Python venv systemd unit for an OCI
        container (podman). Turns on the `/ui` admin route — which
        requires DATABASE_URL + Prisma engines that are not shippable
        from nixpkgs for platform `linux-nixos`, so the container is
        the only realistic path. When `false` (default), the legacy
        systemd unit is active and the UI is unreachable.
      '';
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/berriai/litellm-database:main-stable";
      description = ''
        Container image used when `useOciContainer = true`. The
        `-database` suffix variant bundles Prisma's Rust query +
        schema engines and runs `prisma generate` + `prisma db push`
        at start — mandatory for the UI route. Pin a specific tag in
        production; `main-stable` is a moving target.
      '';
    };

    postgres = {
      image = mkOption {
        type = types.str;
        default = "docker.io/library/postgres:16-alpine";
        description = ''
          Sidecar Postgres image for UI metadata + virtual-key storage.
          Fully-qualified registry to avoid podman short-name lookup
          ambiguity (same treatment as `local.tikvOci.*Image`).
        '';
      };
      port = mkOption {
        type = types.port;
        default = 5433;
        description = ''
          Host-bound port for the sidecar Postgres. Non-default (5432)
          so it can coexist with a future nix-native or workload-specific
          Postgres instance (e.g. `local.langgraphOci` which uses 5432).
        '';
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/litellm-pg";
        description = ''
          Bind-mount source for the sidecar Postgres data volume.
          Created with owner uid/gid 999 via `systemd.tmpfiles` — the
          `postgres:16-alpine` image runs as that uid internally.
        '';
      };
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Sops-decrypted file whose content is a single
          `POSTGRES_PASSWORD=<value>` line (systemd EnvironmentFile
          format — passed directly into the postgres container's env).
          Required when `useOciContainer = true` (assertion).
        '';
      };
    };

    saltKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Sops-decrypted file whose content is a single
        `LITELLM_SALT_KEY=<value>` line. LiteLLM uses this key to
        AES-encrypt DB-stored credentials; if it rotates, existing DB
        rows become undecryptable. Generate once with
        `openssl rand -hex 32` and treat as permanent. Required when
        `useOciContainer = true` (assertion).
      '';
    };

    # ── Declarative team / virtual-key provisioning ───────────────────
    # When `useVirtualKeys = true`, the `litellm-team-bootstrap`
    # oneshot hits LiteLLM's admin API on every rebuild to reconcile
    # teams and client keys against the `teams` + `clientKeys` options
    # below. Requires `useOciContainer = true` (the admin API is
    # DB-backed). See `~/.claude/plans/litellm-teams.md` for design.
    useVirtualKeys = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Turn on declarative team/virtual-key provisioning. Requires
        `useOciContainer = true` (the key API lives behind the
        `/team/*` and `/key/*` admin endpoints which need the DB).
        When false, the bootstrap oneshot is inert and clients may
        keep presenting the master key.

        Rollback: flip back to false, rebuild — existing DB rows are
        left in place (harmless; they just stop being referenced by
        clients) and clients fall back to master-key auth via the
        existing `masterKeyFile` path.
      '';
    };

    teams = mkOption {
      type = types.attrsOf teamSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          dev = {
            description = "Interactive-dev clients: claude-code, opencode";
            models = [ "coder-local" "coder-remote" "coder-cloud-claude" ];
            tpm = 200000;
            rpm = 600;
            maxBudget = 50.0;
            budgetDuration = "30d";
          };
          prod = {
            description = "Always-on agents (hermes)";
            models = [ "coder-local" "embedding" ];
            tpm = 60000;
            rpm = 120;
            maxBudget = 10.0;
            budgetDuration = "30d";
          };
        }
      '';
      description = ''
        Declarative LiteLLM teams. Each team's attribute name becomes
        the team's `team_alias` (human-stable handle — the LiteLLM
        `team_id` UUID is generated server-side and stored against the
        alias). The bootstrap oneshot reconciles these against
        `/team/*` on every rebuild: creates missing teams, updates
        drifted fields, never deletes (deletion requires operator
        confirmation via the UI to avoid nuking live budgets).

        `models` is a list of model-group names already declared under
        `modelGroups`; each is passed verbatim into the team's
        `models` field. LiteLLM treats that list as the allow-set.
        No `*` wildcard; listed groups only.
      '';
    };

    clientKeys = mkOption {
      type = types.attrsOf clientKeySubmodule;
      default = { };
      internal = true;
      description = ''
        Aggregate registry of per-client key declarations, populated by
        client modules (programs.claude-code, programs.opencode,
        local.hermes) when their `litellm.team` is set, and by host
        configs directly for clients whose modules don't run on the
        same host as the proxy. Not meant to be set by end-user host
        configs via the client module interface — set `litellm.team`
        on the client module, and it populates the corresponding
        entry here.

        Each entry's `keyAlias` is the stable handle used as the
        idempotency key when calling `/key/generate`.
      '';
    };

    bootstrapRuntimeDir = mkOption {
      type = types.path;
      default = "/run/litellm-oci/keys";
      description = ''
        Runtime directory the bootstrap oneshot writes minted key
        values into. Each client's minted key lands at
        `<bootstrapRuntimeDir>/<client>` (mode 0440, owner
        litellm:litellm). Client modules read from this path as their
        `virtualKeyFile`.
      '';
    };

    litellmVersion = mkOption {
      type = types.str;
      default = "1.52.0";
      description = ''
        PyPI version of `litellm[proxy]` to install into the venv.
        History: https://pypi.org/project/litellm/#history

        Changing this triggers a venv recreation on next service start
        (the wrapper stamps `.litellm-version` and recreates when it
        differs).
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = ''
        Python interpreter the venv is built around. LiteLLM wheels
        currently target Python 3.10 / 3.11 / 3.12.
      '';
    };

    uv = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "uv binary used to bootstrap and update the venv.";
    };

    venvDir = mkOption {
      type = types.path;
      default = "/var/lib/litellm/venv";
      description = ''
        Persistent uv venv location. Survives nixos-rebuilds. Wipe it
        if the Python / LiteLLM version combo drifts incompatibly:
            sudo rm -rf /var/lib/litellm/venv
        and the next service start will rebuild.
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/lib/litellm";
      description = ''
        State directory for LiteLLM. Parent of `venvDir`; also used as
        `$HOME` for the unit so any cache / temp files land here
        instead of /root.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "litellm";
      description = "System user that runs the LiteLLM proxy.";
    };

    group = mkOption {
      type = types.str;
      default = "litellm";
      description = "System group for the LiteLLM proxy.";
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      # Shared config (applies in both venv and OCI modes).
      {
        # Sanity: at least one of (modelGroups, configFile) must be set.
        assertions = [
          {
            assertion = cfg.modelGroups != { } || cfg.configFile != null;
            message = ''
              local.litellm: either `modelGroups` (preferred) or `configFile`
              (legacy) must be set. With neither, the proxy has no upstream
              to route to.
            '';
          }
          {
            assertion = cfg.useVirtualKeys -> cfg.useOciContainer;
            message = ''
              local.litellm.useVirtualKeys requires useOciContainer = true.
              The key-provisioning admin API depends on a DB.
            '';
          }
          {
            assertion = lib.all (team: lib.all (m: cfg.modelGroups ? ${m}) team.models) (
              lib.attrValues cfg.teams
            );
            message = ''
              local.litellm.teams: every team's `models` entry must reference a
              model-group declared under `local.litellm.modelGroups`. Unknown
              model-groups detected: ${
                lib.concatStringsSep ", " (
                  lib.flatten (
                    lib.mapAttrsToList (_: t: lib.filter (m: !(cfg.modelGroups ? ${m})) t.models) cfg.teams
                  )
                )
              }
            '';
          }
          {
            assertion = lib.all (k: cfg.teams ? ${k.team}) (lib.attrValues cfg.clientKeys);
            message = ''
              local.litellm.clientKeys: every client's `team` must reference a
              team declared under `local.litellm.teams`.
            '';
          }
          {
            # `key_alias` uniqueness — LiteLLM enforces at the API layer (409)
            # but catching at eval gives a clearer error.
            assertion =
              let
                aliases = lib.mapAttrsToList (_: k: k.keyAlias) cfg.clientKeys;
              in
              lib.length aliases == lib.length (lib.unique aliases);
            message = ''
              local.litellm.clientKeys: `keyAlias` values must be unique across
              all client entries. LiteLLM's `/key/generate` keys on alias, so
              collisions would silently shadow each other.
            '';
          }
        ];

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

        # Always create the litellm user/group, even in OCI mode — sops
        # secrets declared with `owner = "litellm"` (e.g. litellm-master-key)
        # are installed by the activation script, which chowns them to that
        # user unconditionally. Removing the user on the OCI path would
        # break the sops-install-secrets activation snippet.
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.cacheDir;
          createHome = true;
          description = "LiteLLM proxy";
        };
        users.groups.${cfg.group} = { };
      }

      # ── venv / systemd path (legacy, default) ────────────────────────
      (mkIf (!cfg.useOciContainer) {
        systemd.tmpfiles.rules = [
          "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
          # Parent of venvDir so uv can create the venv dir itself.
          "d ${builtins.dirOf cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
        ];

        systemd.services.litellm = {
          description = "LiteLLM proxy (OpenAI-compatible federator)";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = {
            HOME = cfg.cacheDir;
            # OTEL routing for LiteLLM's `otel` success/failure callbacks
            # (declared in the rendered config under `litellm_settings`).
            # Phoenix accepts OTLP/HTTP protobuf on /v1/traces.
            OTEL_EXPORTER_OTLP_ENDPOINT = cfg.metrics.otelEndpoint;
            OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
            # libstdc++ (from the pip-installed grpcio / tiktoken wheels)
            # and zlib aren't on NixOS's global library path. Pip wheels
            # assume an FHS layout and dlopen() these at import time, so
            # without LD_LIBRARY_PATH the proxy crash-loops on module load.
            LD_LIBRARY_PATH = lib.makeLibraryPath [
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ];
          }
          // cfg.extraEnv;

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.cacheDir;

            ExecStart = startScript;

            # EnvironmentFile is a list: master-key first, then every
            # per-client virtual-key file. systemd merges them in declared
            # order, so later entries overwrite earlier ones — the master
            # key and virtual keys use distinct variable names
            # (LITELLM_MASTER_KEY vs. LITELLM_API_KEY_<CLIENT>) so no
            # accidental overwrite.
            EnvironmentFile =
              lib.optional (cfg.masterKeyFile != null) cfg.masterKeyFile ++ lib.attrValues cfg.virtualKeys;

            # Cold starts pull the litellm wheel (~100 MiB of deps); give
            # enough headroom for slow network.
            TimeoutStartSec = "10min";

            Restart = "on-failure";
            RestartSec = "15s";
            StartLimitBurst = 5;
            StartLimitIntervalSec = "10min";

            # Sandboxing. Read-only elsewhere; cacheDir + venvDir writable
            # for the venv bootstrap.
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadWritePaths = [
              cfg.cacheDir
              cfg.venvDir
              (builtins.dirOf cfg.venvDir)
            ];
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            LockPersonality = true;
          };
        };
      })

      # ── OCI container path ────────────────────────────────────────────
      # Mirrors the `langgraph-oci` / `tikv-oci` patterns already in this
      # flake: `virtualisation.oci-containers` (podman backend), host
      # networking, a preStart oneshot overriding the generated
      # `podman-<name>.service` to render a runtime EnvironmentFile with
      # the sops-decrypted password spliced into DATABASE_URL (so the
      # plaintext password never appears in the container's `environment`
      # attrset nor in `podman inspect`).
      (mkIf cfg.useOciContainer {
        assertions = [
          {
            assertion = cfg.masterKeyFile != null;
            message = ''
              local.litellm.masterKeyFile is required in OCI mode
              (container reads LITELLM_MASTER_KEY via EnvironmentFile).
            '';
          }
          {
            assertion = cfg.saltKeyFile != null;
            message = ''
              local.litellm.saltKeyFile is required in OCI mode. LiteLLM
              AES-encrypts DB-stored credentials with this key; losing it
              renders the DB undecryptable.
            '';
          }
          {
            assertion = cfg.postgres.passwordFile != null;
            message = ''
              local.litellm.postgres.passwordFile is required in OCI
              mode (sidecar Postgres container reads POSTGRES_PASSWORD
              via EnvironmentFile).
            '';
          }
        ];

        # Bind-mount source for the Postgres data volume. The
        # `postgres:16-alpine` image runs as uid 999 internally
        # (postgres user baked into the image); pre-create with that
        # ownership so the initial `initdb` succeeds.
        systemd.tmpfiles.rules = [
          "d ${toString cfg.postgres.dataDir} 0700 999 999 -"
          "d /run/litellm-oci 0750 root root -"
        ];

        virtualisation.oci-containers.backend = mkDefault "podman";

        virtualisation.oci-containers.containers = {
          # Sidecar Postgres for UI + prisma metadata. Host networking
          # so the litellm container can reach it over loopback on
          # cfg.postgres.port without a user-defined bridge.
          litellm-postgres = {
            image = cfg.postgres.image;
            extraOptions = [ "--network=host" ];
            environment = {
              POSTGRES_USER = "litellm";
              POSTGRES_DB = "litellm";
              # Non-default port inside the container too, so with host
              # networking the host-level port and the container-level
              # port match — no translation layer to reason about.
              PGPORT = toString cfg.postgres.port;
            };
            # POSTGRES_PASSWORD=<value> comes from the sops-decrypted file.
            environmentFiles = [ cfg.postgres.passwordFile ];
            volumes = [
              "${toString cfg.postgres.dataDir}:/var/lib/postgresql/data"
            ];
            # `ports` is informational with --network=host; podman
            # ignores it (bind is whatever PGPORT says inside the ctr).
            ports = [
              "127.0.0.1:${toString cfg.postgres.port}:${toString cfg.postgres.port}"
            ];
          };

          # LiteLLM itself. Loads:
          #   - LITELLM_MASTER_KEY and LITELLM_SALT_KEY from sops
          #     EnvironmentFiles (static, nix-store-tracked paths).
          #   - DATABASE_URL from /run/litellm-oci/db-url.env, written
          #     at unit preStart by a systemd override below (so the
          #     Postgres password is spliced in without landing in the
          #     nix store or the `environment` attrset).
          litellm = {
            image = cfg.image;
            # `--env-file` tells podman itself to slurp KEY=VAL lines from
            # the runtime-generated file and pass them into the container's
            # environment. (A systemd-unit `EnvironmentFile=` alone only
            # populates the env of the podman CLI process, not the container
            # — podman doesn't implicitly forward unit env to containers.)
            extraOptions = [
              "--network=host"
              "--env-file=/run/litellm-oci/db-url.env"
            ];
            dependsOn = [ "litellm-postgres" ];
            environment = {
              PORT = toString cfg.port;
              HOST = cfg.host;
              STORE_MODEL_IN_DB = "False";
              OTEL_EXPORTER_OTLP_ENDPOINT = cfg.metrics.otelEndpoint;
              OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
            }
            // cfg.extraEnv;
            environmentFiles = [
              cfg.masterKeyFile
              cfg.saltKeyFile
            ];
            volumes = [
              "${toString effectiveConfigFile}:/app/config.yaml:ro"
            ];
            cmd = [
              "--config"
              "/app/config.yaml"
              "--port"
              (toString cfg.port)
              "--host"
              cfg.host
            ];
          };
        };

        # Render the runtime DATABASE_URL env-file from the sops password
        # (same pattern as `langgraph-oci`'s POSTGRES_URI renderer) and
        # splice it into the litellm container unit via an additive
        # EnvironmentFile override. `oci-containers.*.environmentFiles`
        # only accepts nix-store paths; runtime-generated files need the
        # systemd override route.
        systemd.services."litellm-oci-db-url" = {
          description = "Render runtime env-file (DATABASE_URL + UI creds) for litellm container";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-litellm.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            Group = "root";
          };
          # Emits two things into the runtime env-file that the litellm
          # container reads via `--env-file`:
          #   1. DATABASE_URL with the sops Postgres password spliced in.
          #   2. UI_USERNAME=admin + UI_PASSWORD=<master key value>. LiteLLM
          #      rejects master-key-as-UI-login in recent versions; the UI
          #      requires explicit UI_USERNAME/UI_PASSWORD. Reusing the
          #      master key keeps "simple auth" with a single human-
          #      rememberable credential (ui login == API bearer) rather
          #      than minting a second secret.
          script = ''
            set -eu
            umask 077
            set -a
            . ${toString cfg.postgres.passwordFile}
            . ${toString cfg.masterKeyFile}
            set +a
            install -d -m 0750 -o root -g root /run/litellm-oci
            install -m 0600 -o root -g root /dev/null /run/litellm-oci/db-url.env
            {
              printf 'DATABASE_URL=postgresql://litellm:%s@127.0.0.1:%d/litellm\n' \
                "$POSTGRES_PASSWORD" ${toString cfg.postgres.port}
              printf 'UI_USERNAME=admin\n'
              printf 'UI_PASSWORD=%s\n' "$LITELLM_MASTER_KEY"
            } > /run/litellm-oci/db-url.env
          '';
        };

        systemd.services."podman-litellm" = {
          after = [ "litellm-oci-db-url.service" ];
          requires = [ "litellm-oci-db-url.service" ];
          serviceConfig = {
            # First-boot `prisma db push` against an empty Postgres takes
            # ~15-30s; default podman unit start-timeout is tighter. Keep
            # parity with the venv unit's headroom.
            TimeoutStartSec = lib.mkForce "5min";
          };
        };
      })

      # ── Team / virtual-key bootstrap ─────────────────────────────────
      # Oneshot reconciler: every rebuild, hit the LiteLLM admin API
      # (`/team/*`, `/key/*`) to converge the live DB against the
      # `teams` + `clientKeys` nix options. Minted key values land in
      # `cfg.bootstrapRuntimeDir/<client>` (mode 0440 litellm:litellm)
      # so client wrappers can read them directly as their
      # `virtualKeyFile`. See `~/.claude/plans/litellm-teams.md` for
      # the full design + API-shape rationale.
      (mkIf (cfg.useOciContainer && cfg.useVirtualKeys) {
        systemd.services.litellm-team-bootstrap = {
          description = "Reconcile LiteLLM teams and virtual keys from nix manifest";
          after = [
            "podman-litellm.service"
            "litellm-oci-db-url.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [ "podman-litellm.service" ];
          wantedBy = [ "multi-user.target" ];

          path = with pkgs; [
            curl
            jq
            coreutils
          ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # root so it can chown minted key files to litellm:litellm
            # in /run/litellm-oci/keys.
            User = "root";
            Group = "root";
            EnvironmentFile = cfg.masterKeyFile;
          };

          script = ''
            set -euo pipefail
            umask 077

            install -d -m 0750 -o litellm -g litellm ${cfg.bootstrapRuntimeDir}

            MANIFEST=${teamManifestFile}
            API="http://127.0.0.1:${toString cfg.port}"
            AUTH="Authorization: Bearer ''${LITELLM_MASTER_KEY}"

            # Wait for readiness — the proxy may still be running prisma migrations.
            for i in $(seq 1 60); do
              if curl -fsS -o /dev/null "$API/health/readiness"; then break; fi
              sleep 2
            done

            # ── Teams ──────────────────────────────────────────────────
            # Fetch current teams once; index by team_alias for O(1) lookup.
            existing_teams=$(curl -fsS -H "$AUTH" "$API/team/list")

            for team_alias in $(jq -r '.teams | keys[]' "$MANIFEST"); do
              team_json=$(jq -c --arg a "$team_alias" '.teams[$a]' "$MANIFEST")
              existing_id=$(echo "$existing_teams" | jq -r \
                --arg a "$team_alias" '.[] | select(.team_alias == $a) | .team_id // empty')

              if [ -z "$existing_id" ]; then
                echo "litellm-bootstrap: creating team $team_alias"
                curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
                  "$API/team/new" -d "$(jq -n \
                    --arg alias "$team_alias" \
                    --argjson t "$team_json" \
                    '{team_alias: $alias} + ($t | {models, tpm_limit: .tpm, rpm_limit: .rpm, max_budget: .maxBudget, budget_duration: .budgetDuration, metadata: {description: .description}})')" \
                  > /dev/null
              else
                echo "litellm-bootstrap: updating team $team_alias ($existing_id)"
                curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
                  "$API/team/update" -d "$(jq -n \
                    --arg id "$existing_id" \
                    --argjson t "$team_json" \
                    '{team_id: $id} + ($t | {models, tpm_limit: .tpm, rpm_limit: .rpm, max_budget: .maxBudget, budget_duration: .budgetDuration, metadata: {description: .description}})')" \
                  > /dev/null
              fi
            done

            # Re-fetch teams so we have IDs for key creation.
            existing_teams=$(curl -fsS -H "$AUTH" "$API/team/list")

            # ── Keys ───────────────────────────────────────────────────
            for client in $(jq -r '.keys | keys[]' "$MANIFEST"); do
              key_alias=$(jq -r --arg c "$client" '.keys[$c].keyAlias' "$MANIFEST")
              team_alias=$(jq -r --arg c "$client" '.keys[$c].team'     "$MANIFEST")
              team_id=$(echo "$existing_teams" | jq -r \
                --arg a "$team_alias" '.[] | select(.team_alias == $a) | .team_id')

              if [ -z "$team_id" ]; then
                echo "litellm-bootstrap: team $team_alias missing team_id after upsert, skipping $client" >&2
                continue
              fi

              # /key/info is the canonical lookup by alias; returns 404 when missing.
              if existing=$(curl -fsS -H "$AUTH" "$API/key/info?key_alias=$key_alias" 2>/dev/null); then
                key_value=$(echo "$existing" | jq -r '.info.key // .key // empty')
              else
                key_value=""
              fi

              if [ -z "$key_value" ] || [ "$key_value" = "null" ]; then
                echo "litellm-bootstrap: minting key $key_alias for team $team_alias"
                minted=$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
                  "$API/key/generate" -d "$(jq -n \
                    --arg a "$key_alias" --arg t "$team_id" \
                    '{key_alias: $a, team_id: $t}')")
                key_value=$(echo "$minted" | jq -r '.key')
              else
                echo "litellm-bootstrap: key $key_alias already minted; leaving value intact"
              fi

              # Write plaintext to the runtime file as KEY=VALUE so it's
              # directly consumable as an EnvironmentFile by client shims
              # that use the `cut -d= -f2-` reader (matches the existing
              # wrapper convention for virtualKeyFile).
              dest=${cfg.bootstrapRuntimeDir}/$client
              var_name="LITELLM_API_KEY_$(echo "$client" | tr 'a-z-' 'A-Z_')"
              umask 077
              printf '%s=%s\n' "$var_name" "$key_value" > "$dest.tmp"
              chown litellm:litellm "$dest.tmp"
              chmod 0440 "$dest.tmp"
              mv -f "$dest.tmp" "$dest"
            done
          '';
        };
      })
    ]
  );
}
