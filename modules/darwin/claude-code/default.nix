{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-code;

  # Vertex and LiteLLM paths are mutually exclusive. When litellm.enable
  # is set, the legacy direct vertex env vars and activation-script
  # settings.json content are suppressed in favor of the LiteLLM-routed
  # block. Same pattern as the nixos module.
  useLegacyVertex = cfg.vertex.enable && !cfg.litellm.enable;

  vertexEnvVars = lib.optionalAttrs useLegacyVertex {
    CLAUDE_CODE_USE_VERTEX = "1";
    CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
    ANTHROPIC_VERTEX_PROJECT_ID = cfg.vertex.projectId;
    ANTHROPIC_VERTEX_BASE_URL = cfg.vertex.baseURL;
    CLOUD_ML_REGION = cfg.vertex.region;
  };

  # LiteLLM env vars — same shape as the nixos module. See
  # modules/nixos/claude-code/default.nix for the `cloudPassthrough`
  # rationale.
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

  # OTel pipeline → luna's collector. Same env-var contract as the NixOS
  # module so a Mac wired to luna shows up in the same Grafana dashboards
  # alongside luna-local Claude Code sessions. host.name comes from
  # nix-darwin's networking.hostName (set per-host under systems/).
  telemetryEnvVars = lib.optionalAttrs cfg.telemetry.enable {
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_LOGS_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_PROTOCOL = cfg.telemetry.protocol;
    OTEL_EXPORTER_OTLP_ENDPOINT = cfg.telemetry.endpoint;
    OTEL_METRIC_EXPORT_INTERVAL = toString cfg.telemetry.exportIntervalMs;
    OTEL_RESOURCE_ATTRIBUTES = "service.namespace=claude-code,host.name=${
      config.networking.hostName or "darwin"
    }";
  };

  allEnvVars =
    vertexEnvVars // litellmEnvVars // apiKeyEnvVars // telemetryEnvVars // cfg.environment;

  wrappedClaude = pkgs.symlinkJoin {
    name = "claude-code-wrapped-${cfg.package.version}";
    paths = [ cfg.package ];
    # makeShellWrapper (not makeBinaryWrapper) — the latter dispatches
    # to makeCWrapper on darwin which rejects `--run` (newer nixpkgs
    # behavior, was silent fallthrough before). The shell wrapper is
    # marginally slower at exec but supports the full --run/--prefix
    # flag set we use to splice the virtual-key load.
    nativeBuildInputs = [ pkgs.makeShellWrapper ];
    postBuild =
      let
        setFlags = lib.concatStringsSep " " (
          lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") (
            lib.filterAttrs (_: v: v != "") allEnvVars
          )
        );
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
    # See modules/nixos/claude-code/default.nix for full rationale. Same
    # option surface across nixos + darwin so host configs can flip the
    # enable flag on either platform with identical semantics.
    litellm = {
      enable = lib.mkEnableOption "Route Claude Code through LiteLLM";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://luna.local:4000";
        description = ''
          LiteLLM base URL (serves `/v1/messages` and `/vertex/*`).
          Default uses `luna.local` (mDNS) so Macs on the home LAN
          resolve without extra wiring; NixOS luna itself should
          override to `http://localhost:4000` via its host config.
        '';
      };

      virtualKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Sops-decrypted path to this client's LiteLLM virtual key.
          Content: `KEY=VALUE`; the value is read at wrapper runtime
          and exported as `ANTHROPIC_API_KEY` when `cloudPassthrough
          = false`. On darwin the decrypted file is written by the
          sops-nix activation script to a path under /run/secrets.
        '';
      };

      cloudPassthrough = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Route cloud calls through LiteLLM's `/vertex/*` passthrough
          (apiKeyHelper keeps the gcloud id-token path alive). Flip
          to false to authenticate purely via the virtual key against
          LiteLLM's `/v1/messages` router.
        '';
      };

      defaultGroup = lib.mkOption {
        type = lib.types.str;
        default = "coder-cloud-claude";
        description = "Default LiteLLM model-group for this client.";
      };

      allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "coder-local"
          "coder-remote"
          "coder-cloud-claude"
          "embedding"
        ];
        description = "Informational: model-groups this client may reference.";
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
        default = "http://luna.local:4317";
        description = ''
          OTLP endpoint URL. Defaults to luna's collector on the home LAN;
          override per-host (e.g. `http://192.168.1.57:4317`) if mDNS is
          flaky off-LAN. nix-darwin hosts never run the collector locally
          (no `local.observability` module on darwin), so unlike the NixOS
          module this default isn't loopback-aware.
        '';
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "grpc"
          "http/protobuf"
        ];
        default = "grpc";
        description = "OTLP transport: gRPC (4317) or HTTP/protobuf (4318).";
      };

      exportIntervalMs = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = "Milliseconds between metric exports.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Settings to write to ~/.claude/settings.json";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables to set on the claude wrapper.";
    };
  };

  config = lib.mkIf cfg.enable {
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
    ]
    ++ lib.optionals (cfg.vertex.enable || (cfg.litellm.enable && cfg.litellm.cloudPassthrough)) [
      pkgs.google-cloud-sdk
    ];

    # Generate settings.json and API key helper via activation script.
    # The emitted env block depends on which path is active:
    #   - legacy vertex   -> CLAUDE_CODE_USE_VERTEX + vertex URLs
    #   - litellm + pass  -> ANTHROPIC_BASE_URL = <endpoint>/vertex/v1
    #   - litellm + route -> ANTHROPIC_BASE_URL = <endpoint>/v1 (no apiKey,
    #                        supplied at wrapper run time from sops)
    #
    # nix-darwin only invokes a fixed list of activation-script slots
    # (preActivation / extraActivation / postActivation) — custom names
    # like `claudeCode` build successfully but are never called. Use
    # extraActivation so this actually fires on `darwin-rebuild switch`.
    system.activationScripts.extraActivation.text = lib.mkAfter (
      let
        user = lib.salt.user;

        settingsEnv =
          if cfg.litellm.enable then
            (
              if cfg.litellm.cloudPassthrough then
                {
                  ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/vertex/v1";
                  CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
                }
              else
                {
                  ANTHROPIC_BASE_URL = "${cfg.litellm.endpoint}/v1";
                }
            )
          else if cfg.vertex.enable then
            {
              CLAUDE_CODE_USE_VERTEX = "1";
              CLAUDE_CODE_SKIP_VERTEX_AUTH = "1";
              CLOUD_ML_REGION = cfg.vertex.region;
              ANTHROPIC_VERTEX_PROJECT_ID = cfg.vertex.projectId;
              ANTHROPIC_VERTEX_BASE_URL = cfg.vertex.baseURL;
              CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "1800000";
            }
          else
            { };

        # apiKeyHelper is active for both legacy-vertex and
        # litellm+cloudPassthrough paths (the gcloud id-token is what
        # LiteLLM forwards to vertex-proxy). For litellm-router-only
        # mode, no helper is needed — the wrapper reads the virtual
        # key from sops at invocation time.
        helperActive =
          cfg.apiKeyHelper || (cfg.litellm.enable && cfg.litellm.cloudPassthrough) || useLegacyVertex;

        settingsWithModel =
          cfg.settings
          // {
            model = cfg.model;
            env = (cfg.settings.env or { }) // settingsEnv;
          }
          // lib.optionalAttrs helperActive {
            apiKeyHelper = "~/.claude/get-iam-token.sh";
          };
        settingsJson = builtins.toJSON settingsWithModel;
      in
      ''
        echo "setting up Claude Code..." >&2
        mkdir -p /Users/${user.name}/.claude
        cat > /Users/${user.name}/.claude/settings.json << 'SETTINGS'
        ${settingsJson}
        SETTINGS
        chown -R ${user.name} /Users/${user.name}/.claude
      ''
      + lib.optionalString helperActive ''
        cat > /Users/${user.name}/.claude/get-iam-token.sh << 'TOKENHELPER'
        #!/usr/bin/env bash
        set -euo pipefail
        echo $(gcloud auth print-identity-token 2>/dev/null)
        TOKENHELPER
        chmod +x /Users/${user.name}/.claude/get-iam-token.sh
      ''
    );

    # Load gcloud credentials for Vertex AI (legacy path only; LiteLLM
    # passthrough doesn't need an exported access token at shell init —
    # the apiKeyHelper mints a fresh id-token per-call).
    programs.zsh.shellInit = lib.mkIf useLegacyVertex ''
      if command -v gcloud >/dev/null 2>&1; then
        export GOOGLE_APPLICATION_CREDENTIALS_JSON="$(gcloud auth print-access-token 2>/dev/null || echo "")"
      fi
    '';
  };
}
