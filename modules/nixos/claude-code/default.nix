{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-code;

  # Vertex env vars: only emitted when the legacy vertex path is in use
  # (i.e. the new LiteLLM path is NOT enabled). The two modes are
  # mutually exclusive — baking both sets of env vars simultaneously
  # produces a confused Claude Code that picks vertex-proxy for /messages
  # but also tries to use a LiteLLM bearer. Gate strictly.
  useLegacyVertex = cfg.vertex.enable && !cfg.litellm.enable;

  vertexEnvVars = lib.optionalAttrs useLegacyVertex {
    CLAUDE_CODE_USE_VERTEX = "1";
    CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
    ANTHROPIC_VERTEX_PROJECT_ID = cfg.vertex.projectId;
    ANTHROPIC_VERTEX_BASE_URL = cfg.vertex.baseURL;
    CLOUD_ML_REGION = cfg.vertex.region;
  };

  # LiteLLM env vars. Two sub-shapes:
  #
  #   cloudPassthrough = true:
  #     ANTHROPIC_BASE_URL points at <endpoint>/vertex/v1 (LiteLLM's
  #     passthrough). Client keeps the apiKeyHelper (gcloud id-token);
  #     LiteLLM forwards it to vertex-proxy untouched.
  #
  #   cloudPassthrough = false:
  #     ANTHROPIC_BASE_URL points at <endpoint>/v1 (LiteLLM's router).
  #     Client authenticates with its virtual key via ANTHROPIC_API_KEY,
  #     read from virtualKeyFile at wrapper start.
  #
  # The API key for the router mode is read from virtualKeyFile at
  # wrapper invocation time (via the shell shim below), NOT baked into
  # the wrapper. That keeps the sops-decrypted value out of /nix/store.
  litellmEnvVars = lib.optionalAttrs cfg.litellm.enable (
    if cfg.litellm.cloudPassthrough then
      {
        ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/vertex/v1";
        CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
      }
    else
      {
        ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/v1";
      }
  );

  apiKeyEnvVars = lib.optionalAttrs cfg.apiKeyHelper {
    CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
  };

  # OTel pipeline → luna's collector. Same env-var contract as Anthropic's
  # monitoring guide (https://github.com/anthropics/claude-code-monitoring-guide):
  # CLAUDE_CODE_ENABLE_TELEMETRY=1 turns on emission, then standard OTLP
  # vars route metrics + logs to the configured endpoint. We also tag
  # service.namespace/host.name so multi-machine slicing works in Grafana.
  telemetryEnvVars = lib.optionalAttrs cfg.telemetry.enable {
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = cfg.telemetry.protocol;
    OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.endpoint;
    OTEL_METRIC_EXPORT_INTERVAL = toString cfg.telemetry.exportIntervalMs;
    OTEL_RESOURCE_ATTRIBUTES = "service.namespace=claude-code,host.name=${config.networking.hostName}";
  };

  allEnvVars =
    vertexEnvVars // litellmEnvVars // apiKeyEnvVars // telemetryEnvVars // cfg.environment;

  wrappedClaude = pkgs.symlinkJoin {
    name = "claude-code-wrapped-${cfg.package.version}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild =
      let
        setFlags = lib.concatStringsSep " " (
          lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") (
            lib.filterAttrs (_: v: v != "") allEnvVars
          )
        );
        # When the router (non-passthrough) LiteLLM path is active, read
        # the virtual key from sops-decrypted file at wrapper invocation
        # time and export as ANTHROPIC_API_KEY. --run makes the value
        # re-read on every `claude` invocation, so sops rotation takes
        # effect without a rebuild.
        runHook =
          lib.optionalString
            (cfg.litellm.enable && !cfg.litellm.cloudPassthrough && cfg.litellm.virtualKeyFile != null)
            ''
              --run 'if [ -r "${toString cfg.litellm.virtualKeyFile}" ]; then export ANTHROPIC_API_KEY="$(cut -d= -f2- < "${toString cfg.litellm.virtualKeyFile}")"; fi'
            '';
      in
      ''
        wrapProgram $out/bin/claude ${setFlags} ${runHook}
      '';
  };
in
{
  options.programs.claude-code = {
    enable = lib.mkEnableOption "Claude Code AI assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      description = "The claude-code package to use.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "claude-opus-4-7";
      description = "Default model to use.";
    };

    # ── Legacy vertex path (direct-to-vertex-proxy) ────────────────────
    # Kept for backward compat. When programs.claude-code.litellm.enable
    # is true, this block is ignored (mutually exclusive with the new
    # LiteLLM-routed path).
    vertex = {
      enable = lib.mkEnableOption "Vertex AI proxy for Claude Code (legacy direct path; ignored when litellm.enable = true)";

      projectId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Google Cloud project ID for Vertex AI.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east5";
        description = "Google Cloud region for Vertex AI.";
      };

      baseURL = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Base URL for the Vertex AI proxy.";
      };
    };

    # ── LiteLLM-routed path ───────────────────────────────────────────
    # Preferred shape: Claude Code only knows about LiteLLM's endpoint.
    # Cloud calls are a thin `/vertex/*` passthrough that forwards the
    # client's apiKeyHelper-minted GCP id-token; local calls hit the
    # LiteLLM router under `/v1`, authenticated via a per-client
    # virtual key read from a sops-decrypted file at wrapper run time.
    litellm = {
      enable = lib.mkEnableOption "Route Claude Code through LiteLLM";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = config.local.litellm.endpoint or "http://luna:4000";
        defaultText = lib.literalExpression ''config.local.litellm.endpoint or "http://luna:4000"'';
        description = ''
          LiteLLM base URL. Serves both `/v1/messages` (OpenAI-compat
          router) and `/vertex/*` (passthrough to vertex-proxy).
          Clients never hardcode the host; they reference this.
        '';
      };

      virtualKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Sops-decrypted path to this client's LiteLLM virtual key.
          The file must contain a single `KEY=VALUE` line; `VALUE`
          is exported as `ANTHROPIC_API_KEY` at wrapper invocation
          time when `cloudPassthrough = false`.

          `null` falls back to the proxy's master key via the unit's
          EnvironmentFile path (shared; use only when per-client
          isolation isn't needed — e.g. internal services).
        '';
      };

      cloudPassthrough = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          When true: Claude Code routes through LiteLLM's `/vertex/*`
          passthrough. The existing `apiKeyHelper` (gcloud id-token)
          stays active; LiteLLM forwards the bearer to vertex-proxy
          untouched. This is the right default — keeps cloud
          reachability when the user wants Claude, while still letting
          explicit `claude --model coder-local ...` invocations hit
          LiteLLM's router.

          When false: Claude Code hits `/v1/messages` (LiteLLM's
          OpenAI-compat router). All calls authenticate via the
          virtual key; cloud models are reached via LiteLLM's
          `coder-cloud-claude` model group (pass-through under the
          covers). Use this on hosts that should never ship a GCP
          id-token but still want Claude-flavored completions.
        '';
      };

      defaultGroup = lib.mkOption {
        type = lib.types.str;
        default = "coder-cloud-claude";
        description = ''
          LiteLLM model-group name this client uses as its default.
          The mapping to concrete upstreams lives in
          `config.local.litellm.modelGroups`.
        '';
      };

      allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "coder-local"
          "coder-remote"
          "coder-cloud-claude"
          "embedding"
        ];
        description = ''
          Informational: which model-groups this client is allowed to
          reference. Not enforced inside the wrapper (LiteLLM enforces
          at the router via its virtual-key ACL), but kept so callers
          can audit intent.
        '';
      };

      team = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Name of a team declared under `config.local.litellm.teams` on
          the luna host running the proxy. When set, this client's
          virtual key is scoped to that team and inherits its model ACL
          / rate limits / budget. When null (default), the client
          presents the proxy's master key (shared-key rollback).

          Setting this on luna (same host as the proxy) contributes to
          `local.litellm.clientKeys` automatically so the bootstrap
          oneshot mints the key. On darwin hosts the option is
          informational-only — luna's host config is the source of
          truth for which clients get keys (see the plan at
          `~/.claude/plans/litellm-teams.md`).
        '';
      };

      keyAlias = lib.mkOption {
        type = lib.types.str;
        default = "claude-code-nixos";
        description = ''
          Stable handle used as idempotency key against
          `POST /key/generate`. Keep in sync with the sops file stem
          (`secrets/litellm-key-<alias>.yaml`). On the luna host the
          bootstrap oneshot writes the minted value to
          `/run/litellm-oci/keys/<keyAlias>`.
        '';
      };
    };

    apiKeyHelper = lib.mkEnableOption "API key helper script for Vertex AI";

    telemetry = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Push OTel metrics + logs to a collector. Default-on because the
          SDK silently drops OTLP when the endpoint is unreachable, so a
          laptop off the home LAN behaves identically to one on it. Set
          to false to suppress emission entirely.
        '';
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default =
          if (config.local.observability.enable or false) then
            "http://127.0.0.1:4317"
          else
            "http://luna.local:4317";
        defaultText = lib.literalExpression ''
          if config.local.observability.enable
          then "http://127.0.0.1:4317"
          else "http://luna.local:4317"
        '';
        description = ''
          OTLP endpoint URL. Auto-derived: if this host *is* the collector
          (local.observability.enable = true), defaults to loopback so
          metrics never traverse the network; otherwise defaults to luna's
          published endpoint on the home LAN. Override per-host if neither
          fits (e.g. an off-site box that should push to a tunnel).
        '';
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "grpc"
          "http/protobuf"
        ];
        default = "grpc";
        description = ''
          OTLP transport. gRPC (4317) is the default and what Anthropic's
          reference collector listens on; switch to `http/protobuf` (4318)
          if a network path can't speak HTTP/2.
        '';
      };

      exportIntervalMs = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = ''
          Milliseconds between metric exports. 10s is responsive without
          hammering the collector; bump to 60000 for laptops on cellular.
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings to write to /etc/claude-code/settings.json";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables to set on the claude wrapper.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !(cfg.vertex.enable && cfg.litellm.enable);
            message = ''
              programs.claude-code: vertex.enable and litellm.enable are
              mutually exclusive. Pick one — either the legacy direct
              vertex-proxy path (vertex.enable) or the new LiteLLM-routed
              path (litellm.enable).
            '';
          }
        ];

        environment.systemPackages = [
          wrappedClaude
          pkgs.bubblewrap
          pkgs.socat
        ]
        # google-cloud-sdk is needed for either path: legacy vertex uses it
        # directly; LiteLLM passthrough also needs it because the wrapper's
        # apiKeyHelper shells out to `gcloud auth print-identity-token`.
        ++ lib.optionals (cfg.vertex.enable || (cfg.litellm.enable && cfg.litellm.cloudPassthrough)) [
          pkgs.google-cloud-sdk
        ];

        # System-wide settings
        environment.etc."claude-code/settings.json".text = builtins.toJSON (
          cfg.settings
          // {
            model = cfg.model;
          }
        );

        # Profile.d env: only emitted for the legacy vertex path so
        # interactive shells (and random subprocesses that read env from
        # /etc/profile.d) see the same CLAUDE_CODE_* / ANTHROPIC_VERTEX_*
        # values the wrapper bakes in. The LiteLLM path doesn't need this —
        # the wrapper is self-contained and there's no shell-exported
        # apiKeyHelper contract to maintain.
        environment.etc."profile.d/claude-code.sh" = lib.mkIf useLegacyVertex {
          text = ''
            export CLAUDE_CODE_USE_VERTEX=1
            export CLAUDE_CODE_SKIP_VERTEX_AUTH=1
            export ANTHROPIC_VERTEX_PROJECT_ID="${cfg.vertex.projectId}"
            export ANTHROPIC_VERTEX_BASE_URL="${cfg.vertex.baseURL}"
            export CLOUD_ML_REGION="${cfg.vertex.region}"
          '';
        };
      }

      # Contribute to the aggregate clientKeys registry on the host
      # running the proxy. Gated on litellm.team != null so hosts that
      # only use the master-key rollback path don't materialize a DB row.
      (lib.mkIf (cfg.litellm.enable && cfg.litellm.team != null) {
        local.litellm.clientKeys.${cfg.litellm.keyAlias} = {
          team = cfg.litellm.team;
          keyAlias = cfg.litellm.keyAlias;
          # luna reads /run/litellm-oci/keys directly; no sops round-
          # trip needed for this host's own key. Host configs that want
          # the minted value materialized into a sops yaml (e.g. to
          # propagate to darwin hosts) can override via
          # `local.litellm.clientKeys.<alias>.sopsFile = ...`.
          sopsFile = null;
        };
      })
    ]
  );
}
