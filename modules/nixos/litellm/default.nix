# LiteLLM proxy as a systemd service.
#
# LiteLLM (https://docs.litellm.ai/) is an OpenAI-compatible federator:
# one HTTP surface in front of many upstream model backends (vLLM, exo,
# hosted OpenAI, hosted Anthropic, etc.). luna uses it as the "coder
# router" in front of the local vLLM (:8000) and the exo / GFR-exo
# federation, exposed to LangGraph workers at :4000.
#
# Packaging approach (mirrors `modules/nixos/vllm/default.nix` and
# `modules/nixos/mcpo/default.nix`):
#   * `litellm[proxy]` ships on PyPI. We install it into a uv-managed
#     venv at first service start, pinned by `cfg.litellmVersion`. The
#     venv is version-stamped and auto-recreated on version bumps.
#   * Master key (bearer token clients present to the proxy) is loaded
#     at unit start via `EnvironmentFile` from a sops-decrypted file,
#     NOT baked into the YAML config. The YAML references
#     `os.environ/LITELLM_MASTER_KEY` which LiteLLM evaluates at
#     config-load time.
#
# Usage:
#   local.litellm = {
#     enable = true;
#     configFile = ../../../projects/swarm/litellm_config.yaml;
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
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
      --quiet \
      "litellm[proxy]==$LITELLM_VERSION" \
      "setuptools"

    echo "$LITELLM_VERSION" > "$VERSION_STAMP"

    exec "$VENV/bin/litellm" \
      --config "${toString cfg.configFile}" \
      --port "${toString cfg.port}" \
      --host "${cfg.host}"
  '';
in
{
  options.local.litellm = {
    enable = mkEnableOption "LiteLLM proxy (OpenAI-compatible federator)";

    configFile = mkOption {
      type = types.path;
      description = ''
        Path to the LiteLLM YAML config. The file is read by the proxy
        at start; it may reference env vars via the `os.environ/<NAME>`
        syntax, which LiteLLM evaluates at config-load time.
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

        The referenced config (`cfg.configFile`) should point
        `general_settings.master_key` at `os.environ/LITELLM_MASTER_KEY`
        so the env var is what's actually in effect.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — the
        proxy is authenticated via the master key, but the master key
        is a weak secret on its own; only flip this on for LAN-trusted
        hosts.
      '';
    };

    phoenixEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:6006/v1/traces";
      description = ''
        OTLP HTTP endpoint Phoenix listens on. LiteLLM's `otel` success
        / failure callbacks export spans here so router decisions show
        up alongside LangGraph traces.
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
        # (declared in the YAML under `litellm_settings`). Phoenix
        # accepts OTLP/HTTP protobuf on /v1/traces.
        OTEL_EXPORTER_OTLP_ENDPOINT = cfg.phoenixEndpoint;
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

        # EnvironmentFile must be a single line of the form KEY=VALUE
        # (systemd's own env-file format). The sops secret is formatted
        # that way upstream so it drops in without further plumbing.
        EnvironmentFile = mkIf (cfg.masterKeyFile != null) cfg.masterKeyFile;

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
