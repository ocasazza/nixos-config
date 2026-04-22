# Open WebUI as a chat frontend for the local vLLM endpoint(s).
#
# Open WebUI talks to any OpenAI-compatible backend via OPENAI_API_BASE_URLS,
# so we just hand it the URLs from `local.vllm.services` and the model
# selector in the UI populates from `/v1/models` automatically. Adding a
# new vllm service (e.g. an embedding endpoint) wires it into the chat UI
# on the next switch — no extra config needed here.
#
# What this module owns:
#   * `services.open-webui` enable + port + state dir
#   * Auto-wiring of `OPENAI_API_BASE_URLS` from local.vllm.services
#   * A sensible default env block (telemetry off, signup gated) that can
#     be overridden via `extraEnvironment`
#   * Declarative admin-user seeding via `WEBUI_ADMIN_EMAIL` /
#     `WEBUI_ADMIN_PASSWORD` / `WEBUI_ADMIN_NAME` + a static
#     `WEBUI_SECRET_KEY` so every rebuild deterministically materializes
#     the same admin account without a manual UI first-signup.
#   * Declarative API-key upsert for the admin — required because Open
#     WebUI upstream has no `DEFAULT_USER_API_KEY` env var; the ingest
#     pipeline needs a known `sk-<hex>` token to authenticate, so we
#     pin the admin's row in the `api_key` table at each rebuild. This
#     is declarative-by-wrapping-imperative (we run a sqlite3 UPSERT in
#     a oneshot post-start unit) because upstream exposes no cleaner
#     seam. See the `open-webui-seed-api-key` unit below.
#
# What it does NOT own (yet):
#   * TLS / reverse proxy — fine on a LAN-only box, add caddy/nginx later
#   * Embedding model wiring — once luna serves an embedding endpoint,
#     either set `embeddingEndpoint` here or let users pick it via the UI
#   * RAG document store — Open WebUI's built-in vector DB is enough for
#     ad-hoc uploads; the Obsidian vault is queried by LocalGPT, not here
#
# Usage (full declarative, e.g. from luna):
#   local.openWebUI = {
#     enable = true;
#     openFirewall = true;
#
#     # Consumed by upstream's create_admin_user() during lifespan
#     # startup; when cfg.admin.email/password are set the module wires
#     # WEBUI_ADMIN_EMAIL/PASSWORD/NAME into the environment file.
#     admin = {
#       email = "admin@luna.local";
#       passwordFile = config.sops.secrets.openwebui-admin-password.path;
#       # Stable WEBUI_SECRET_KEY so JWTs survive rebuilds; without this
#       # open-webui writes a random one to $stateDir/.webui_secret_key.
#       secretKeyFile = config.sops.secrets.openwebui-secret-key.path;
#       # Pinned API token for the admin — the `api_key` table row is
#       # upserted at every rebuild to match this file's contents.
#       apiKeyFile = config.sops.secrets.openwebui-api-token.path;
#     };
#   };
#
# Verify (after `nixos-rebuild switch`):
#   curl -sS http://luna.local:8080/health
#   curl -sS -H "Authorization: Bearer $(sudo cat /run/secrets/openwebui-api-token)" \
#     http://luna.local:8080/api/v1/knowledge/
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.openWebUI;
  vllmCfg =
    config.local.vllm or {
      enable = false;
      services = { };
    };

  # Auto-derive backend URLs from every enabled vLLM service. Open WebUI
  # accepts a `;`-separated list in OPENAI_API_BASE_URLS and probes each
  # one's `/models` endpoint to populate the model picker.
  derivedEndpoints = mapAttrsToList (_: svc: "http://127.0.0.1:${toString svc.port}/v1") (
    if vllmCfg.enable then vllmCfg.services else { }
  );

  endpoints = if cfg.openaiBaseURLs != null then cfg.openaiBaseURLs else derivedEndpoints;

  # vLLM ignores Authorization but Open WebUI sends one regardless and
  # bails if OPENAI_API_KEYS is empty. The literal "none" matches what
  # the Open WebUI docs recommend for upstreams without auth.
  apiKeys = map (_: cfg.apiKey) endpoints;

  # Admin seeding is opt-in: only declared when both email and password
  # file are set. This lets `extraEnvironment` users who prefer the
  # first-signup flow keep using it.
  adminSeedEnabled = cfg.admin.email != null && cfg.admin.passwordFile != null;

  apiKeySeedEnabled = adminSeedEnabled && cfg.admin.apiKeyFile != null;

  baseEnvironment = {
    # Bind explicitly; the upstream module's `host` option also passes
    # this but we set it for any sub-process / health probe that reads
    # the env directly.
    HOST = cfg.host;
    PORT = toString cfg.port;

    # Backend wiring. `;` separator is Open WebUI's convention.
    OPENAI_API_BASE_URLS = concatStringsSep ";" endpoints;
    OPENAI_API_KEYS = concatStringsSep ";" apiKeys;

    # No Ollama — we serve through vllm only. Disabling the probe avoids
    # a noisy startup log line every restart.
    ENABLE_OLLAMA_API = "false";

    # Auth posture: signup on by default so the first browser hit creates
    # the admin user. Flip `signupEnabled = false` after that to lock the
    # instance down. When `admin.email` + `admin.passwordFile` are set
    # we override this to `false` — the admin is seeded declaratively, so
    # no signup is needed.
    ENABLE_SIGNUP = boolToString (if adminSeedEnabled then false else cfg.signupEnabled);
    DEFAULT_USER_ROLE = cfg.defaultUserRole;
    WEBUI_AUTH = boolToString cfg.requireAuth;

    # API-key issuance. The admin's key is pinned by the seed unit below,
    # but the *feature flag* (`ENABLE_API_KEYS`) is a PersistentConfig —
    # when `ENABLE_PERSISTENT_CONFIG` is false (below) env always wins,
    # so we set both to guarantee the admin user can actually wield an
    # `sk-<hex>` bearer token regardless of the DB's prior config row.
    ENABLE_API_KEYS = boolToString cfg.enableApiKeys;

    # Pin env over any pre-existing `config.json` / persistent-config
    # table values. Without this, a stale DB value for (e.g.) signup
    # policy silently overrides the env we pass here and the "declarative
    # config" illusion leaks. See Open WebUI's config.py::PersistentConfig.
    ENABLE_PERSISTENT_CONFIG = "False";

    # Seed the admin account from the upstream env vars at lifespan
    # startup. `WEBUI_ADMIN_PASSWORD` is loaded from the sops-rendered
    # env file in `environment = { ... }`-merged form (see the
    # systemd.services.open-webui merge below).
    WEBUI_ADMIN_NAME = cfg.admin.name;
    # Email is the lone plaintext here — it's an identifier, not a
    # secret, so baking it into the nix store is fine.
  }
  // lib.optionalAttrs (cfg.admin.email != null) {
    WEBUI_ADMIN_EMAIL = cfg.admin.email;
  }
  // lib.optionalAttrs cfg.disableTelemetry {
    # Don't phone home. The dataset Open WebUI sends to its analytics
    # endpoint includes model names and prompt lengths.
    ANONYMIZED_TELEMETRY = "false";
    SCARF_NO_ANALYTICS = "true";
    DO_NOT_TRACK = "true";
  }
  // lib.optionalAttrs (!cfg.enableRagEmbedding) {
    # Speedy first paint — skip the embedded HF model download for the
    # built-in semantic search; the user can enable it later if they
    # want vault-less RAG over uploaded docs.
    RAG_EMBEDDING_ENGINE = "";
  };

  # Seed script — runs after open-webui.service is listening on the
  # configured port. Polls /health until ready (upstream's lifespan
  # blocks on admin creation, so once /health returns the admin row
  # exists), then upserts the `api_key` row for the configured admin
  # email to match the plaintext of cfg.admin.apiKeyFile.
  #
  # DECLARATIVE-BY-WRAPPING-IMPERATIVE NOTE:
  # Open WebUI exposes no `DEFAULT_USER_API_KEY` / `ADMIN_API_KEY` env
  # var. The only way to pin a known bearer token for service-to-service
  # auth (ingest → open-webui Knowledge API) is to write the row into
  # the `api_key` table ourselves. Every rebuild produces the same row
  # (idempotent UPSERT on primary key `key_<user_id>`), so this behaves
  # like declarative config even though it's a runtime DB mutation.
  # Revisit if upstream ever ships a first-class env-var path.
  seedScript = pkgs.writeShellScript "open-webui-seed-api-key" ''
    set -eu

    DB="${cfg.stateDir}/data/webui.db"
    HEALTH_URL="http://127.0.0.1:${toString cfg.port}/health"
    ADMIN_EMAIL="${toString cfg.admin.email}"
    API_KEY_FILE="${toString cfg.admin.apiKeyFile}"

    # Wait for open-webui to finish lifespan startup. create_admin_user
    # runs before the HTTP server starts accepting connections, so once
    # /health returns 200 the admin row is guaranteed present.
    echo "seed: waiting for open-webui /health..."
    for i in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null; then
        break
      fi
      sleep 2
    done

    if ! ${pkgs.curl}/bin/curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null; then
      echo "seed: open-webui never became healthy" >&2
      exit 1
    fi

    if [ ! -f "$DB" ]; then
      echo "seed: $DB does not exist (first boot before lifespan init?); bailing" >&2
      exit 0
    fi

    API_KEY="$(cat "$API_KEY_FILE")"
    if [ -z "$API_KEY" ]; then
      echo "seed: api key file is empty; refusing to seed" >&2
      exit 1
    fi

    # Resolve the admin user id. Prefer the configured email; fall back
    # to any user with role=admin (covers the case where the instance
    # predates admin-email config and was seeded via first-signup under
    # a different address).
    USER_ID="$(${pkgs.sqlite}/bin/sqlite3 "$DB" \
      "SELECT id FROM user WHERE email = '$ADMIN_EMAIL' LIMIT 1;")"
    if [ -z "$USER_ID" ]; then
      USER_ID="$(${pkgs.sqlite}/bin/sqlite3 "$DB" \
        "SELECT id FROM user WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1;")"
    fi

    if [ -z "$USER_ID" ]; then
      echo "seed: no admin user found in $DB; skipping api-key seed" >&2
      exit 0
    fi

    echo "seed: upserting api_key row for user $USER_ID"
    NOW="$(date +%s)"
    # Idempotent UPSERT keyed on the stable primary key
    # `key_<user_id>` that upstream's update_user_api_key_by_id uses.
    ${pkgs.sqlite}/bin/sqlite3 "$DB" <<SQL
BEGIN IMMEDIATE;
DELETE FROM api_key WHERE user_id = '$USER_ID';
INSERT INTO api_key (id, user_id, key, created_at, updated_at)
VALUES ('key_' || '$USER_ID', '$USER_ID', '$API_KEY', $NOW, $NOW);
COMMIT;
SQL
    echo "seed: done"
  '';

in
{
  options.local.openWebUI = {
    enable = mkEnableOption "Open WebUI chat frontend for local vLLM";

    package = mkOption {
      type = types.package;
      default = pkgs.open-webui;
      defaultText = literalExpression "pkgs.open-webui";
      description = "open-webui derivation to run.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Defaults to all interfaces so the LAN can reach the
        UI. Set to `127.0.0.1` if you put a reverse proxy in front for
        TLS / auth.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "HTTP port for the Open WebUI server.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — Open WebUI
        ships without TLS and the first-user-becomes-admin signup model
        means a LAN attacker can claim the instance if it's exposed
        before you've created an account.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = ''
        Directory holding the SQLite DB, uploaded files, vector store,
        and per-user settings. Back this up if you care about chat
        history and shared prompts.
      '';
    };

    openaiBaseURLs = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = literalExpression ''[ "http://127.0.0.1:8000/v1" ]'';
      description = ''
        OpenAI-compatible backend URLs. Default `null` means: derive
        them automatically from every entry in `local.vllm.services`.
        Set explicitly to override (e.g. to add a remote OpenAI proxy
        alongside the local vllm).
      '';
    };

    apiKey = mkOption {
      type = types.str;
      default = "none";
      description = ''
        API key sent to every upstream. vLLM ignores it but Open WebUI
        requires the env var be non-empty. The literal `none` is the
        Open WebUI convention for unauthenticated upstreams.
      '';
    };

    signupEnabled = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Allow new users to sign up via the UI. Leave on for the first
        boot (first signup becomes admin), then flip to false to seal
        the instance. Forced to `false` when `admin.email` +
        `admin.passwordFile` are set (the admin is seeded from env).
      '';
    };

    requireAuth = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Require a logged-in user to access the UI. Set false only for a
        single-user box behind a trusted network — Open WebUI without
        auth is essentially a public REST proxy to the upstream model.
      '';
    };

    defaultUserRole = mkOption {
      type = types.enum [
        "pending"
        "user"
        "admin"
      ];
      default = "pending";
      description = ''
        Role assigned to new signups after the first (which is always
        admin). `pending` means the admin must approve them — sane
        default for a household instance.
      '';
    };

    enableApiKeys = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set the `ENABLE_API_KEYS` env var, the gate upstream checks before
        accepting `sk-<hex>` bearer tokens. Defaults to true because the
        ingest pipeline's `openwebui` sink relies on it.
      '';
    };

    disableTelemetry = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set `ANONYMIZED_TELEMETRY=false`, `SCARF_NO_ANALYTICS=true`,
        `DO_NOT_TRACK=true`. Open WebUI's telemetry payload includes
        model names and prompt lengths; off by default.
      '';
    };

    enableRagEmbedding = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Let Open WebUI download its built-in sentence-transformer on
        first boot for ad-hoc-upload RAG. Off by default to keep
        startup fast on a headless host; the Obsidian vault has its
        own RAG pipeline anyway.
      '';
    };

    admin = {
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "admin@luna.local";
        description = ''
          Seeds the admin account on first boot via Open WebUI's
          `WEBUI_ADMIN_EMAIL` env var. When set alongside `passwordFile`
          the module also flips `ENABLE_SIGNUP` to false (the admin is
          materialized declaratively, no first-signup needed). `null`
          disables admin seeding (stock first-signup flow).
        '';
      };

      name = mkOption {
        type = types.str;
        default = "Admin";
        description = ''
          Display name for the seeded admin user
          (`WEBUI_ADMIN_NAME`). Cosmetic only.
        '';
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing the admin user's password. Consumed
          via sops-nix → sops.templates → a rendered env file wired into
          `services.open-webui.environmentFile`. Only used on FIRST boot
          (upstream's `create_admin_user` is a no-op once any user
          exists); rotate by deleting the user row or by re-seeding a
          new admin email.
        '';
      };

      secretKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing `WEBUI_SECRET_KEY` (used by Open
          WebUI for JWT signing). When unset Open WebUI auto-generates
          one at `''${stateDir}/.webui_secret_key`, which is fine for a
          single-host deployment but makes rebuild → JWT invalidation
          non-deterministic. Pin this from sops for reproducibility.
        '';
      };

      apiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing the plaintext `sk-<32-hex>` API
          token that the module should pin into the admin user's row
          in Open WebUI's `api_key` table. Needed for service-to-service
          auth (ingest pipeline → Open WebUI Knowledge API) because
          upstream has no env-var equivalent. The module runs a oneshot
          post-start unit that upserts the row idempotently on every
          rebuild. Leave `null` if you don't need a pinned API token.
        '';
      };
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Extra env vars merged into Open WebUI's environment. Anything
        from the Open WebUI docs (https://docs.openwebui.com/getting-started/env-configuration)
        is fair game.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Sanity: starting Open WebUI without any backend means the model
      # picker sits empty and every chat fails. Warn loudly.
      assertions = [
        {
          assertion = (length endpoints) > 0;
          message = ''
            local.openWebUI.enable = true but no backends are configured:
            either enable `local.vllm.services` or set
            `local.openWebUI.openaiBaseURLs` explicitly.
          '';
        }
        {
          # Can't pin an API key without an admin to own it.
          assertion = !apiKeySeedEnabled || adminSeedEnabled;
          message = ''
            local.openWebUI.admin.apiKeyFile is set but admin.email +
            admin.passwordFile are not — can't pin an API-key row
            without a deterministic admin user to attach it to.
          '';
        }
      ];

      services.open-webui = {
        enable = true;
        package = cfg.package;
        host = cfg.host;
        port = cfg.port;
        stateDir = cfg.stateDir;
        openFirewall = cfg.openFirewall;
        environment = baseEnvironment // cfg.extraEnvironment;
      };
    }

    # Render the secret-bearing env file via sops templates and wire it
    # into the service's `environmentFile`. We keep plaintext values out
    # of the nix store entirely: the template content is interpolated
    # at sops activation time from the decrypted sops secrets.
    (mkIf adminSeedEnabled {
      sops.templates."open-webui.env" = {
        # DynamicUser=true in the upstream module means the unit's
        # runtime UID isn't stable. Keep the file root-owned + mode 0400;
        # systemd reads EnvironmentFile as root before dropping privs.
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          WEBUI_ADMIN_PASSWORD=${config.sops.placeholder.openwebui-admin-password}
        ''
        + lib.optionalString (cfg.admin.secretKeyFile != null) ''
          WEBUI_SECRET_KEY=${config.sops.placeholder.openwebui-secret-key}
        '';
      };

      services.open-webui.environmentFile = config.sops.templates."open-webui.env".path;
    })

    # API-key seeder. Runs after open-webui.service is up; upserts the
    # admin's row in the `api_key` table from the plaintext token file.
    (mkIf apiKeySeedEnabled {
      systemd.services.open-webui-seed-api-key = {
        description = "Open WebUI: pin admin API key from sops";
        after = [ "open-webui.service" ];
        bindsTo = [ "open-webui.service" ];
        wantedBy = [ "multi-user.target" ];
        # sqlite3 + curl are invoked via absolute /nix/store paths
        # inside the script; no PATH surface needed.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = seedScript;
          # The script reads cfg.admin.apiKeyFile (mode 0400 root) and
          # writes to the sqlite db in cfg.stateDir. open-webui's unit
          # uses DynamicUser so the db is owned by a dynamic uid under
          # /var/lib/private/open-webui; systemd's StateDirectory alias
          # `/var/lib/open-webui` is the same dir. Running as root is
          # the simplest way to get write access without matching the
          # dynamic uid.
          User = "root";
          Group = "root";
          ProtectSystem = "strict";
          ReadWritePaths = [ (toString cfg.stateDir) ];
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    })
  ]);
}
