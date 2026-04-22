# LangGraph Server as a declarative systemd service.
#
# Runs one `langgraph dev` process per configured project, each pulling
# its own dependencies from its own `uv` lockfile. The pattern mirrors
# `modules/nixos/vllm/default.nix`:
#   - Per-project persistent venv under `cfg.venvDir/<name>`.
#   - uv creates the venv against `cfg.python`, then pip-installs the
#     project in editable mode (`--project <projectDir>`) so the venv
#     honors the project's own `pyproject.toml` / `uv.lock`.
#   - A `.langgraph-python-version` stamp triggers venv rebuild on
#     python version drift.
#
# Why `langgraph dev` (not `langgraph up`):
#   - `langgraph up` requires Docker + LangSmith API key — neither of
#     which we want on luna for a first-pass self-host. It also uses
#     docker-compose for orchestration, which conflicts with the
#     "declarative systemd service" brief.
#   - `langgraph dev` runs natively, serves the same Studio API on
#     --host/--port, persists runs to in-memory SQLite by default, and
#     has a `--no-browser` flag that matches a headless service.
#   - Trade-off: no Postgres by default → run durability across
#     restarts is zero. That's acceptable for dev; a future commit can
#     bolt on `services.postgresql` + `databaseUrl` and the module will
#     wire it through (the option is already plumbed).
#
# Usage:
#   local.langgraphServer = {
#     enable = true;
#     projects = {
#       swarm  = { projectDir = "/home/casazza/swarm";  port = 2024; openFirewall = true; };
#       ingest = { projectDir = "/home/casazza/ingest"; port = 2025; };
#     };
#   };
#
# Verify:
#   curl http://luna.local:2024/ok    # health check
#   curl http://luna.local:2024/info  # graph registry
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.langgraphServer;

  # Submodule for one project entry in cfg.projects.
  projectOpts =
    { name, ... }:
    {
      options = {
        projectDir = mkOption {
          type = types.path;
          description = ''
            Filesystem path to a `langgraph.json`-bearing project. The
            project's own `pyproject.toml` / `uv.lock` drive the venv.
          '';
        };

        port = mkOption {
          type = types.port;
          description = "HTTP listen port for `langgraph dev`.";
        };

        host = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Bind address. Default `0.0.0.0` so the LAN can reach it;
            flip to `127.0.0.1` if you want to front it with a reverse
            proxy for auth (langgraph dev itself has no auth).
          '';
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Open the listen port in the host firewall. Off by default —
            langgraph dev serves the Studio API with no authentication,
            so only expose it behind a reverse proxy on a trusted LAN.
          '';
        };

        databaseUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "postgresql://langgraph:secret@localhost:5432/langgraph";
          description = ''
            Postgres URL for durable runs. When null, langgraph dev
            falls back to in-memory SQLite — runs evaporate on restart
            but the server needs no external dependency. Set this once
            you add a real `services.postgresql` + role.
          '';
        };

        phoenixEndpoint = mkOption {
          type = types.str;
          default = "http://localhost:6006/v1/traces";
          description = ''
            Phoenix OTLP HTTP trace endpoint. Exported to each service
            as `OTEL_EXPORTER_OTLP_ENDPOINT` + `PHOENIX_COLLECTOR_ENDPOINT`
            so graph spans land in the same trace tree as swarm/ingest.
          '';
        };

        llmBaseUrl = mkOption {
          type = types.str;
          default = "http://localhost:4000/v1";
          description = ''
            LiteLLM proxy base URL. Exported as `OPENAI_API_BASE` so
            graphs that use `langchain-openai` hit the swarm's shared
            backend pool (vllm + exo + etc.) instead of a hardcoded
            model host.
          '';
        };

        llmApiKey = mkOption {
          type = types.str;
          default = "sk-swarm-local";
          description = ''
            LiteLLM proxy master key. Matches `master_key` in
            `~/swarm/litellm_config.yaml`. Exported as
            `OPENAI_API_KEY`. Not a real secret — LiteLLM is LAN-only
            — so literal string here is fine; switch to a *File
            option if you ever expose the proxy publicly.
          '';
        };

        env = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = ''
            Extra environment variables for this project's service.
            Merged after the default OTEL / OPENAI / DATABASE_URL keys,
            so entries here win on conflict.
          '';
        };

        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [
            "--no-browser"
            "--no-reload"
          ];
          description = ''
            Extra CLI flags passed to `langgraph dev`. Defaults:
              `--no-browser` — never try to open a browser under systemd
              `--no-reload`  — no hot-reload in production; avoids the
                               stat-storm on the project tree
          '';
        };
      };
    };

  # Per-project venv bootstrap. Runs at service start; idempotent. When
  # the project's uv.lock has changed since the last sync, `uv pip
  # install --project <dir>` re-resolves and updates the venv in place.
  venvBootstrap =
    name: proj:
    pkgs.writeShellScript "langgraph-${name}-venv" ''
      set -eu

      VENV="${cfg.venvDir}/${name}"
      VERSION="${cfg.pythonVersion}"
      STAMP="$VENV/.langgraph-python-version"

      if [ -x "$VENV/bin/python" ] && [ -f "$STAMP" ]; then
        installed="$(cat "$STAMP")"
        if [ "$installed" != "$VERSION" ]; then
          echo "langgraph-${name}: python version changed ($installed → $VERSION), recreating venv"
          rm -rf "$VENV"
        fi
      fi

      if [ ! -x "$VENV/bin/python" ]; then
        echo "langgraph-${name}: bootstrapping venv at $VENV"
        ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
      fi

      echo "langgraph-${name}: installing langgraph-cli[inmem] + project deps"
      # Always pull the CLI + API server. `inmem` extra unlocks the
      # in-process SQLite checkpointer that `langgraph dev` uses when
      # no --postgres-uri is set.
      ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" --quiet \
        "langgraph-cli[inmem]"

      # Install the project itself in editable mode, honoring its own
      # pyproject.toml / uv.lock. Every graph-side dependency
      # (langchain-openai, langchain-mcp-adapters, etc.) comes from
      # here so the service picks up pyproject bumps on restart
      # without needing a new rebuild.
      ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" --quiet \
        --editable "${toString proj.projectDir}"

      echo "$VERSION" > "$STAMP"
    '';

  # ExecStart wrapper — reads secrets from disk (none today, but the
  # shape matches the vllm/ingest wrappers so adding a `*File` option
  # later is trivial) and execs langgraph dev bound into the venv.
  startScript =
    name: proj:
    let
      langgraphArgs = lib.escapeShellArgs (
        [
          "dev"
          "--config"
          "${toString proj.projectDir}/langgraph.json"
          "--host"
          proj.host
          "--port"
          (toString proj.port)
        ]
        ++ proj.extraArgs
      );
    in
    pkgs.writeShellScript "langgraph-${name}-start" ''
      set -eu

      VENV="${cfg.venvDir}/${name}"

      ${venvBootstrap name proj}

      # `langgraph dev` is installed as a console script under
      # $VENV/bin/langgraph. Exec directly — the interpreter line in
      # that wrapper already points at $VENV/bin/python.
      exec "$VENV/bin/langgraph" ${langgraphArgs}
    '';

  # Environment shared across every project. Secrets stay null-safe.
  baseEnv =
    name: proj:
    {
      HOME = toString cfg.cacheDir;
      LANGGRAPH_STATE_DIR = "${toString cfg.cacheDir}/${name}";
      # OTEL → Phoenix. Set both the generic OTLP env and Phoenix's
      # own name so anything in the project that reads either picks
      # it up.
      OTEL_EXPORTER_OTLP_ENDPOINT = proj.phoenixEndpoint;
      PHOENIX_COLLECTOR_ENDPOINT = proj.phoenixEndpoint;
      OTEL_SERVICE_NAME = "langgraph-${name}";
      # LiteLLM → swarm's shared backend pool.
      OPENAI_API_BASE = proj.llmBaseUrl;
      OPENAI_API_KEY = proj.llmApiKey;
    }
    // lib.optionalAttrs (proj.databaseUrl != null) {
      # langgraph-cli reads DATABASE_URI (the canonical langgraph
      # name) for the runs store. Also exporting DATABASE_URL for
      # projects that use SQLAlchemy-style names.
      DATABASE_URI = proj.databaseUrl;
      DATABASE_URL = proj.databaseUrl;
    };

  enabledProjects = cfg.projects;

  # Union of per-project firewall ports.
  firewallPorts = lib.pipe enabledProjects [
    (lib.filterAttrs (_: p: p.openFirewall))
    (lib.mapAttrsToList (_: p: p.port))
  ];
in

{
  options.local.langgraphServer = {
    enable = mkEnableOption "LangGraph Server (scheduled graph runs + API)";

    projects = mkOption {
      type = types.attrsOf (types.submodule projectOpts);
      default = { };
      description = ''
        Map of project-name → project configuration. Each entry spawns
        a dedicated `langgraph-<name>` systemd service pinned to its
        own venv under `cfg.venvDir/<name>`.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = ''
        Python interpreter the venvs are built around. langgraph-cli
        targets >=3.11 as of the 0.2.x line; 3.12 matches what swarm
        and ingest already pin in their pyproject files.
      '';
    };

    pythonVersion = mkOption {
      type = types.str;
      default = "3.12";
      description = "Stamped into each venv so drift triggers a rebuild.";
    };

    uv = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "uv binary used to bootstrap and update venvs.";
    };

    user = mkOption {
      type = types.str;
      default = "langgraph";
      description = "System user that runs all langgraph-server services.";
    };

    group = mkOption {
      type = types.str;
      default = "langgraph";
      description = "System group paired with `user`.";
    };

    venvDir = mkOption {
      type = types.path;
      default = "/var/lib/langgraph/venv";
      description = ''
        Parent directory for per-project venvs. Each project gets its
        own `<venvDir>/<project-name>` subdir — isolated so bumping
        one project's deps can't bleed into another.
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/lib/langgraph";
      description = ''
        State / cache dir root. Houses HuggingFace, pip, and
        langgraph-cli's own caches. Persistent across reboots.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = toString cfg.cacheDir;
      createHome = true;
      description = "LangGraph Server";
    };

    systemd.tmpfiles.rules = [
      "d ${toString cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${toString cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = firewallPorts;

    # One long-running service per project.
    systemd.services = lib.mapAttrs' (
      name: proj:
      lib.nameValuePair "langgraph-${name}" {
        description = "LangGraph Server (${name}: ${toString proj.projectDir})";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        # uv's venv bootstrap shells out to a C compiler + linker when
        # any transitive dep has to build a native wheel (numpy's
        # fallback path, pyzmq, etc.). systemd services start with a
        # near-empty PATH, so without this the first install dies with
        # `cc: command not found`.
        path = [
          pkgs.gcc
          pkgs.binutils
          pkgs.git
        ];

        environment = baseEnv name proj // proj.env;

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = toString proj.projectDir;

          ExecStart = startScript name proj;

          # First boot pip-install can take several minutes for the
          # langgraph-api + openinference instrumentation stack.
          TimeoutStartSec = "20min";

          Restart = "on-failure";
          RestartSec = "15s";
          StartLimitBurst = 5;
          StartLimitIntervalSec = "10min";

          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            (toString cfg.cacheDir)
            (toString cfg.venvDir)
          ];
          # uv editable-install writes .egg-info / __pycache__ under
          # projectDir — the bind-mount restores RW access under
          # ProtectHome=true.
          BindPaths = [ (toString proj.projectDir) ];
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;

          LimitNOFILE = 65536;
        };
      }
    ) enabledProjects;
  };
}
