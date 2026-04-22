# LangGraph free-self-hosted production stack, via OCI containers.
#
# Why this module exists (and why `local.langgraphServer` is left in place):
#   * `local.langgraphServer` wraps `langgraph dev`, which upstream itself
#     labels "designed for development and testing". That code path
#     defaults to an in-memory SQLite checkpointer; a `langgraph dev`
#     restart drops every scheduled run. The existing module's
#     `databaseUrl` option is also not plumbed into the invocation, so
#     even pointing at Postgres wouldn't help today.
#   * The free (no-LangSmith-API-key, no-Enterprise-license) self-host
#     path is the `langchain/langgraph-api` image running in two modes
#     (API + queue worker), talking to a shared Postgres + Redis. This
#     is documented by upstream at:
#       - https://docs.langchain.com/langsmith/deploy-standalone-server
#       - LangChain forum "Free self-hosted LangGraph agent server —
#         how to separate API and queue workers using Docker"
#     The forum thread is the authoritative source for the worker-role
#     entrypoint override:
#       ["python", "-m", "langgraph_api.queue_entrypoint"]
#     and the `N_JOBS_PER_WORKER=0` env-var on the API role that stops
#     the API container from claiming runs itself.
#
# Topology (per enabled project):
#
#   ┌──────────────────────┐    ┌─────────────────────────┐
#   │ langgraph-api-<name> │    │ langgraph-worker-<name> │
#   │ langchain/langgraph- │    │ same image, entrypoint  │
#   │ api + N_JOBS_PER_    │    │ python -m langgraph_api │
#   │ WORKER=0             │    │ .queue_entrypoint       │
#   └─────────┬────────────┘    └────────────┬────────────┘
#             │                              │
#             │       POSTGRES_URI           │
#             │       REDIS_URI              │
#             ▼                              ▼
#          ┌──────────────────────────────────────┐
#          │  services.postgresql (host, unix)    │
#          │  services.redis.servers.langgraph    │
#          │    (127.0.0.1:6380, loopback, no    │
#          │     password — containers hit it    │
#          │     over host networking)            │
#          └──────────────────────────────────────┘
#
# Host networking is used (--network=host) to match the tikv-oci pattern
# on luna and to make the Postgres/Redis loopback-only topology Just Work
# (the containers share luna's netns, so 127.0.0.1:5432 and :6380 point
# at the same nixpkgs-managed services luna is hosting natively). A
# consequence: the API port is bound by the container process directly
# on the host's 0.0.0.0/127.0.0.1 — `ports` attrs are carried for docs
# but podman ignores them with host networking.
#
# Project bind-mount: the brief puts projectDir in read-only bind at
# /deps/<name>. The base `langchain/langgraph-api` image does NOT have
# user project code baked in (that's what `langgraph build` would do —
# this module skips `langgraph build` to stay declarative), so we
# pip-install each project in editable mode at container start with
# the image's own constraints file (`/api/constraints.txt`) — this is
# the exact same loop the CLI-generated Dockerfile runs at build time
# (see `libs/cli/langgraph_cli/config.py`, the
#  `RUN for dep in /deps/*; do … pip install -c /api/constraints.txt -e .; done`
# template). Editable installs write .egg-info into the bind-mount; we
# keep the mount RW for that reason even though the "intent" is RO.
#
# Schema migrations: `langgraph-api`'s own entrypoint auto-migrates the
# Postgres schema on startup. No `langgraph db init` step is required
# (and that subcommand doesn't exist as of the 0.2.x CLI).
#
# This module is parallel-track: it does NOT set `local.langgraphOci.
# enable = true` on luna. The user flips the switch after validating the
# stack. See `local.langgraphServer` (still enabled on luna on 2024/2025)
# for the currently-live code path; this module defaults to 2026/2027.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.langgraphOci;

  # Bind-address prefix for port publishing. Loopback-only when
  # `openFirewall` is false. Host networking means `ports` is informational,
  # but future switch to bridged would use this.
  bindHost = project: if project.openFirewall then "0.0.0.0" else "127.0.0.1";

  # Per-project container start-command. The base image ships pip +
  # /api/constraints.txt. We editable-install every bind-mounted project
  # under /deps so the runtime can import the user's graph modules, then
  # hand off to either the API default entrypoint or the worker override.
  #
  # `role` is "api" or "worker". The image's default entrypoint starts
  # uvicorn on :8000 under the regular Python runtime; the worker's
  # queue_entrypoint drains the Redis-backed job queue and never opens
  # a socket.
  startCmd =
    role:
    let
      execLine =
        if role == "api" then
          # Default entrypoint from the base image (uvicorn on :8000).
          # `exec` replaces the shell so systemd sees the real PID.
          "exec /api/entrypoint.sh"
        else
          "exec python -m langgraph_api.queue_entrypoint";
    in
    [
      "/bin/sh"
      "-c"
      ''
        set -eu
        # Install every project bind-mounted under /deps in editable
        # mode, using the image's own constraints file. Mirrors the
        # CLI-generated Dockerfile's install loop exactly (see file
        # header). Safe to re-run — pip notices `already satisfied` and
        # skips network round-trips.
        for dep in /deps/*; do
          if [ -d "$dep" ]; then
            echo "langgraph-oci: installing $dep"
            (
              cd "$dep"
              PYTHONDONTWRITEBYTECODE=1 pip install \
                --no-cache-dir -c /api/constraints.txt -e .
            )
          fi
        done
        ${execLine}
      ''
    ];

  # Shared env: POSTGRES_URI + REDIS_URI + LANGSERVE_GRAPHS per project.
  # The image reads `POSTGRES_URI` (not DATABASE_URI) and `REDIS_URI`
  # per the forum thread. Password is loaded from a file by a systemd
  # oneshot that renders an EnvironmentFile; POSTGRES_URI is injected
  # that way so the plaintext password never shows up in the container
  # env-map nor in `podman inspect`.
  baseEnv = name: project: {
    # Redis — dedicated loopback instance on port 6380 (seaweedfs uses
    # 6379, this is a parallel instance so langgraph state is isolated).
    REDIS_URI = "redis://127.0.0.1:${toString cfg.redis.port}";
    # Graph registry. The CLI would normally bake this into the image
    # via the `LANGSERVE_GRAPHS` ENV in the generated Dockerfile; here
    # we inject it at runtime with absolute paths under /deps/<name>.
    # The in-image resolver expects either a module path
    # (`pkg.module:attr`) or a filesystem path. We read the project's
    # own langgraph.json, prefix each file-style graph with
    # /deps/<name>/, and re-emit as JSON.
    LANGSERVE_GRAPHS = builtins.toJSON (
      lib.mapAttrs (
        _: target:
        if lib.hasPrefix "./" target then "/deps/${name}/" + (lib.removePrefix "./" target) else target
      ) (builtins.fromJSON (builtins.readFile "${toString project.projectDir}/langgraph.json")).graphs
    );
    # Pip cache inside the container (RW under the bind-mount's volume
    # sibling). Writable — can't use /deps because that's the user's
    # project tree.
    PIP_CACHE_DIR = "/var/cache/langgraph-pip";
  };

  # Systemd ordering targets. podman-<container>.service is the unit
  # name rendered by the oci-containers module.
  postgresUnit = "postgresql.service";
  redisUnit = "redis-langgraph.service";

in
{
  options.local.langgraphOci = {
    enable = mkEnableOption ''
      Free self-hosted LangGraph production stack (API + worker pair per
      project, shared Postgres + Redis). Parallel-track with the
      existing `local.langgraphServer` (`langgraph dev`) module — do not
      enable both on the same ports
    '';

    image = mkOption {
      type = types.str;
      default = "docker.io/langchain/langgraph-api:latest";
      description = ''
        Full OCI image reference for both the API and worker role.
        Pin to a specific tag (e.g. `:0.2.75`) in production — the
        `:latest` tag is updated frequently and a surprise pull can
        break your graphs on `nixos-rebuild`. Rotate tags via a PR so
        the bump is reviewable.
      '';
    };

    projects = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              projectDir = mkOption {
                type = types.path;
                description = ''
                  Filesystem path to a `langgraph.json`-bearing project.
                  Bind-mounted into `/deps/<name>` inside both the API
                  and worker containers. Editable-installed at container
                  start using the image's `/api/constraints.txt`.
                '';
              };
              port = mkOption {
                type = types.port;
                description = ''
                  Host port the API container listens on. The image's
                  default entrypoint binds uvicorn on :8000 inside the
                  container; with host networking, that's the host port
                  directly, so this value is passed as PORT (the image's
                  entrypoint respects it).
                '';
              };
              openFirewall = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Open this project's API port on the host firewall.
                  Off by default — the image ships no auth; expose only
                  behind a reverse proxy, or keep on loopback.
                '';
              };
              env = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = ''
                  Extra env-vars for both the API and worker containers
                  of this project. Merged on top of the module's
                  REDIS_URI + LANGSERVE_GRAPHS defaults, so entries here
                  win on conflict. Typical: per-project OPENAI_API_BASE,
                  OPENAI_API_KEY, OTEL endpoints.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Map of project-name → project configuration. Each enabled entry
        spawns a pair of systemd-managed podman containers:
        `podman-langgraph-api-<name>.service` and
        `podman-langgraph-worker-<name>.service`.
      '';
    };

    postgres = {
      user = mkOption {
        type = types.str;
        default = "langgraph";
        description = "Postgres role that owns the langgraph database.";
      };
      databaseName = mkOption {
        type = types.str;
        default = "langgraph";
        description = "Postgres database name for langgraph state.";
      };
      port = mkOption {
        type = types.port;
        default = 5432;
        description = ''
          Postgres listen port. Default 5432. If another host-level
          Postgres is running you will need to either migrate to the
          shared instance or move this one.
        '';
      };
      passwordFile = mkOption {
        type = types.path;
        description = ''
          Path to a file containing the Postgres password for
          `cfg.postgres.user`. Loaded by a systemd oneshot that runs
          `ALTER USER … WITH PASSWORD …` after Postgres comes up, and
          re-read into an EnvironmentFile for the langgraph containers.
          Recommended: sops-nix secret at
          `secrets/langgraph-pg-password.yaml`.
        '';
      };
    };

    redis = {
      port = mkOption {
        type = types.port;
        default = 6380;
        description = ''
          Dedicated loopback Redis port for LangGraph's pub-sub. Default
          6380 to avoid colliding with the seaweedfs Redis on 6379. No
          auth — loopback-only posture.
        '';
      };
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/langgraph-oci";
      description = "Pip cache shared across API + worker containers.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/langgraph-oci";
      description = "Persistent state dir (currently unused; reserved).";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.backend = mkDefault "podman";

    # Host-level Postgres + Redis. Both are nixpkgs-native services
    # (not containers) — much simpler than containerizing them, and the
    # data lives under /var/lib/postgresql where it survives rebuilds.
    services.postgresql = {
      enable = true;
      ensureDatabases = [ cfg.postgres.databaseName ];
      ensureUsers = [
        {
          name = cfg.postgres.user;
          ensureDBOwnership = true;
        }
      ];
      # Listen on loopback only. The langgraph containers (host-
      # networked) hit 127.0.0.1:5432 the same way any in-host client
      # would. No TLS configured — loopback posture.
      enableTCPIP = true;
      settings.listen_addresses = lib.mkDefault "127.0.0.1";
      authentication = lib.mkOverride 10 ''
        # TYPE  DATABASE       USER            ADDRESS                 METHOD
        local   all            all                                     trust
        host    all            all             127.0.0.1/32            md5
        host    all            all             ::1/128                 md5
      '';
    };

    services.redis.servers.langgraph = {
      enable = true;
      bind = "127.0.0.1";
      port = cfg.redis.port;
      # No password — loopback-only, same posture as the future
      # internal-only LiteLLM proxy. If this is ever LAN-exposed, wire
      # a requirePassFile and surface it via REDIS_URI above.
    };

    # Open firewall for per-project API ports with openFirewall = true.
    networking.firewall.allowedTCPPorts = lib.pipe cfg.projects [
      (lib.filterAttrs (_: p: p.openFirewall))
      (lib.mapAttrsToList (_: p: p.port))
    ];

    # Shared pip cache dir — must pre-exist so podman's bind-mount
    # doesn't silently create it as root-owned with the wrong mode.
    systemd.tmpfiles.rules = [
      "d ${toString cfg.cacheDir} 0755 root root -"
      "d ${toString cfg.stateDir} 0750 root root -"
      "d /run/langgraph-oci        0750 root root -"
    ];

    # Systemd units: combine (a) the Postgres-password seeder oneshot
    # (b) per-project env-file renderers that populate POSTGRES_URI
    # from the sops file at unit-start (keeps the plaintext out of the
    # nix store AND out of `podman inspect` arg-lists), and
    # (c) ordering / EnvironmentFile wiring for each of the podman-
    # generated langgraph-{api,worker}-<name>.service units.
    systemd.services = {
      postgresql-langgraph-password = {
        description = "Seed langgraph Postgres role password from sops";
        after = [ postgresUnit ];
        wants = [ postgresUnit ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
        };
        script = ''
          set -eu
          PW="$(cat ${toString cfg.postgres.passwordFile})"
          # ALTER USER is idempotent — safe to re-run on every boot
          # and picks up password rotations (edit the sops yaml +
          # rebuild).
          ${config.services.postgresql.package}/bin/psql \
            -v ON_ERROR_STOP=1 \
            -c "ALTER USER ${cfg.postgres.user} WITH PASSWORD '$PW';"
        '';
      };
    }
    // (lib.mapAttrs' (
      name: _project:
      lib.nameValuePair "langgraph-oci-env-${name}" {
        description = "Render POSTGRES_URI env-file for langgraph-${name}";
        after = [
          postgresUnit
          redisUnit
        ];
        wants = [
          postgresUnit
          redisUnit
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
        };
        script = ''
          set -eu
          umask 077
          PW="$(cat ${toString cfg.postgres.passwordFile})"
          mkdir -p /run/langgraph-oci
          cat > /run/langgraph-oci/${name}.env <<EOF
          POSTGRES_URI=postgres://${cfg.postgres.user}:$PW@127.0.0.1:${toString cfg.postgres.port}/${cfg.postgres.databaseName}?sslmode=disable
          EOF
          chmod 0600 /run/langgraph-oci/${name}.env
        '';
      }
    ) cfg.projects)
    // (lib.concatMapAttrs (name: _project: {
      "podman-langgraph-api-${name}" = {
        after = [
          postgresUnit
          redisUnit
          "langgraph-oci-env-${name}.service"
        ];
        requires = [ "langgraph-oci-env-${name}.service" ];
        serviceConfig = {
          EnvironmentFile = "/run/langgraph-oci/${name}.env";
        };
      };
      "podman-langgraph-worker-${name}" = {
        after = [
          postgresUnit
          redisUnit
          "langgraph-oci-env-${name}.service"
          "podman-langgraph-api-${name}.service"
        ];
        requires = [ "langgraph-oci-env-${name}.service" ];
        serviceConfig = {
          EnvironmentFile = "/run/langgraph-oci/${name}.env";
        };
      };
    }) cfg.projects);

    # The actual container definitions. One API + one worker per project.
    virtualisation.oci-containers.containers = lib.concatMapAttrs (
      name: project:
      let
        sharedEnv = baseEnv name project // project.env;
        # The API container env: same as shared plus N_JOBS_PER_WORKER=0
        # (per the forum thread — stops the API from claiming runs
        # itself so the worker always drains the queue).
        apiEnv = sharedEnv // {
          N_JOBS_PER_WORKER = "0";
          PORT = toString project.port;
        };
        workerEnv = sharedEnv;
      in
      {
        "langgraph-api-${name}" = {
          image = cfg.image;
          extraOptions = [ "--network=host" ];
          # `ports` is carried for docs — with --network=host, podman
          # honors the container's own listen binding instead. The image's
          # entrypoint reads PORT (set above), so host port == container
          # port == project.port.
          ports = [
            "${bindHost project}:${toString project.port}:${toString project.port}"
          ];
          volumes = [
            "${toString project.projectDir}:/deps/${name}"
            "${toString cfg.cacheDir}:/var/cache/langgraph-pip"
          ];
          environment = apiEnv;
          cmd = startCmd "api";
        };

        "langgraph-worker-${name}" = {
          image = cfg.image;
          extraOptions = [ "--network=host" ];
          volumes = [
            "${toString project.projectDir}:/deps/${name}"
            "${toString cfg.cacheDir}:/var/cache/langgraph-pip"
          ];
          environment = workerEnv;
          dependsOn = [ "langgraph-api-${name}" ];
          cmd = startCmd "worker";
        };
      }
    ) cfg.projects;
  };
}
