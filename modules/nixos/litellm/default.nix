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

  config = mkIf cfg.enable {
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
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.cacheDir;
      createHome = true;
      description = "LiteLLM proxy";
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
      # Parent of venvDir so uv can create the venv dir itself.
      "d ${builtins.dirOf cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

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
  };
}
