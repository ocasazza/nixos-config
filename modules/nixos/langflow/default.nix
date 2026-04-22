# Langflow as a declarative systemd service.
#
# Langflow (https://docs.langflow.org/) is a browser-based visual
# builder for LangChain flows — components-on-a-canvas UX where each
# node is a langchain runnable, and the composed graph can be exported
# to Python / deployed as an API. Complements the code-driven
# `local.langgraphServer` (swarm, ingest) with an experimentation +
# rapid-iteration surface: build a flow in the UI, point it at the
# same LiteLLM proxy the scripted graphs use, export to Python once
# the shape stabilizes.
#
# Packaging approach (mirrors `modules/nixos/phoenix/default.nix`):
#   * `langflow` ships on PyPI. We install it into a uv-managed venv
#     at first service start, pinned by `cfg.langflowVersion`. The
#     venv is version-stamped and auto-recreated on version bumps.
#   * Flow DB + uploaded files land under `cfg.workingDir`
#     (default `/var/lib/langflow`). SQLite by default; point
#     `cfg.databaseUrl` at Postgres for production-shaped durability
#     (matches the `local.langgraphOci` option shape).
#
# Ports:
#   * cfg.port (default 7860) — Langflow HTTP + UI. Authless by
#     default; same posture as `local.langgraphServer` — treat
#     `openFirewall = true` as "LAN-trusted only".
#
# Consumer wiring (out of the box):
#   * OPENAI_API_BASE → LiteLLM proxy at :4000, so every
#     langchain-openai node in a Langflow flow hits the same shared
#     backend pool (vllm + exo + etc.) as the scripted graphs.
#   * OTEL_EXPORTER_OTLP_ENDPOINT + PHOENIX_COLLECTOR_ENDPOINT →
#     Phoenix at :6006, so flow-authored spans land in the same
#     trace tree as swarm/ingest.
#
# Usage:
#   local.langflow = {
#     enable = true;
#     openFirewall = true;
#   };
#
# Verify (after switch):
#   curl http://luna.local:7860/health_check   # liveness
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.langflow;

  # Bootstrap a uv-managed venv at first start, pip-install pinned
  # langflow, stamp the version, then exec `langflow run`. Idempotent
  # across restarts; version drift triggers a full venv rebuild.
  startScript = pkgs.writeShellScript "langflow-start" ''
    set -eu

    VENV="${cfg.venvDir}"
    LANGFLOW_VERSION="${cfg.langflowVersion}"
    VERSION_STAMP="$VENV/.langflow-version"

    if [ -x "$VENV/bin/python" ] && [ -f "$VERSION_STAMP" ]; then
      installed_version="$(cat "$VERSION_STAMP")"
      if [ "$installed_version" != "$LANGFLOW_VERSION" ]; then
        echo "langflow: version changed ($installed_version -> $LANGFLOW_VERSION), recreating venv"
        rm -rf "$VENV"
      fi
    fi

    if [ ! -x "$VENV/bin/python" ]; then
      echo "langflow: bootstrapping venv at $VENV"
      ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
    fi

    # `setuptools` is kept in the install list for the same reason as
    # phoenix / litellm / vllm: transitive deps lazy-import it at
    # runtime.
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
      --quiet \
      "langflow==$LANGFLOW_VERSION" \
      "setuptools"

    echo "$LANGFLOW_VERSION" > "$VERSION_STAMP"

    exec "$VENV/bin/langflow" run \
      --host "${cfg.host}" \
      --port "${toString cfg.port}" \
      --backend-only="${if cfg.backendOnly then "true" else "false"}"
  '';
in
{
  options.local.langflow = {
    enable = mkEnableOption "Langflow (visual LangChain flow builder)";

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Default `0.0.0.0` so LAN browsers can reach the
        UI. Flip to `127.0.0.1` if you're fronting it with a reverse
        proxy for auth (Langflow itself ships no auth by default).
      '';
    };

    port = mkOption {
      type = types.port;
      default = 7860;
      description = "HTTP port for the Langflow UI + API.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — Langflow
        has no authentication, so only flip this on for LAN-trusted
        hosts (same posture as `local.langgraphServer`).
      '';
    };

    backendOnly = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Serve only the API / backend, without the React frontend. Useful
        when fronting with a separate static-UI host, but for the
        single-box luna topology the default (frontend+backend) is what
        you want.
      '';
    };

    workingDir = mkOption {
      type = types.path;
      default = "/var/lib/langflow";
      description = ''
        Langflow state directory — SQLite flow DB, uploaded files, run
        artifacts. Exported as `LANGFLOW_CONFIG_DIR` at service start.
        Persistent across reboots.
      '';
    };

    databaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "postgresql://langflow:secret@localhost:5432/langflow";
      description = ''
        Postgres URL for durable flows. When null, Langflow falls back
        to SQLite under `cfg.workingDir` — fine for a single-node setup
        where flows are edited interactively and deploy targets run
        elsewhere. Exported as `LANGFLOW_DATABASE_URL`.
      '';
    };

    phoenixEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:6006/v1/traces";
      description = ''
        Phoenix OTLP HTTP trace endpoint. Exported as
        `OTEL_EXPORTER_OTLP_ENDPOINT` + `PHOENIX_COLLECTOR_ENDPOINT`
        so flow runs show up in the same trace tree as swarm/ingest.
      '';
    };

    llmBaseUrl = mkOption {
      type = types.str;
      default = "http://localhost:4000/v1";
      description = ''
        LiteLLM proxy base URL. Exported as `OPENAI_API_BASE` so
        langchain-openai components in a flow hit the swarm's shared
        backend pool instead of hardcoded model hosts.
      '';
    };

    llmApiKey = mkOption {
      type = types.str;
      default = "sk-swarm-local";
      description = ''
        LiteLLM proxy master key. Matches
        `projects/swarm/litellm_config.yaml`. Exported as
        `OPENAI_API_KEY`. Not a real secret — LiteLLM is LAN-only —
        so literal-string is fine.
      '';
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra environment variables exported to the Langflow process.
        See https://docs.langflow.org/environment-variables for the
        full list of `LANGFLOW_*` variables (LANGFLOW_AUTO_LOGIN,
        LANGFLOW_SUPERUSER, LANGFLOW_LOG_LEVEL, etc.).
      '';
    };

    langflowVersion = mkOption {
      type = types.str;
      default = "1.0.19.post2";
      description = ''
        PyPI version of `langflow` to install into the venv.
        History: https://pypi.org/project/langflow/#history

        Changing this triggers a venv recreation on next service start
        (the wrapper stamps `.langflow-version` and recreates when it
        differs). 1.0.x is the current stable; 1.1.x reworks components
        so it's worth pinning deliberately rather than tracking latest.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = ''
        Python interpreter the venv is built around. Langflow 1.0.x
        targets Python 3.10–3.12.
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
      default = "/var/lib/langflow/venv";
      description = ''
        Persistent uv venv location. Survives nixos-rebuilds. Wipe it
        if Python / Langflow version drift makes imports break:
            sudo rm -rf /var/lib/langflow/venv
      '';
    };

    user = mkOption {
      type = types.str;
      default = "langflow";
      description = "System user that runs Langflow.";
    };

    group = mkOption {
      type = types.str;
      default = "langflow";
      description = "System group for Langflow.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.workingDir;
      createHome = true;
      description = "Langflow";
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.workingDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${builtins.dirOf cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.langflow = {
      description = "Langflow (visual LangChain flow builder)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # uv's venv bootstrap shells out to a C compiler + linker when a
      # transitive dep has to build a native wheel. systemd services
      # start with a near-empty PATH, so surface gcc / ld / git here.
      path = [
        pkgs.gcc
        pkgs.binutils
        pkgs.git
      ];

      environment = {
        HOME = cfg.workingDir;
        LANGFLOW_CONFIG_DIR = cfg.workingDir;
        # OPENAI_* → LiteLLM. PHOENIX / OTEL → Phoenix. Same contract
        # as `local.langgraphServer` so Langflow flows interoperate
        # with the rest of the swarm out of the box.
        OPENAI_API_BASE = cfg.llmBaseUrl;
        OPENAI_API_KEY = cfg.llmApiKey;
        OTEL_EXPORTER_OTLP_ENDPOINT = cfg.phoenixEndpoint;
        PHOENIX_COLLECTOR_ENDPOINT = cfg.phoenixEndpoint;
        OTEL_SERVICE_NAME = "langflow";
        # Pip-wheel deps (grpcio, tiktoken, psycopg2-binary) dlopen
        # libstdc++ / libz at import time assuming an FHS layout.
        LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ];
      }
      // lib.optionalAttrs (cfg.databaseUrl != null) {
        LANGFLOW_DATABASE_URL = cfg.databaseUrl;
      }
      // cfg.extraEnv;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workingDir;

        ExecStart = startScript;

        # Cold starts pull the langflow wheel + its LangChain component
        # tree (~400 MiB of deps); give plenty of headroom.
        TimeoutStartSec = "25min";

        Restart = "on-failure";
        RestartSec = "15s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = "10min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [
          cfg.workingDir
          cfg.venvDir
          (builtins.dirOf cfg.venvDir)
        ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;

        LimitNOFILE = 65536;
      };
    };
  };
}
