# MCPO — MCP-to-OpenAPI proxy (https://github.com/open-webui/mcpo).
#
# MCPO is the canonical bridge for wiring stdio MCP servers into Open WebUI.
# It spawns any number of MCP servers as child processes, multiplexes their
# tool schemas into one OpenAPI surface per server, and serves them at
#   http://<host>:<port>/<server-name>/openapi.json
#   http://<host>:<port>/<server-name>/docs
# which Open WebUI's Admin → Settings → Tools registers as a "tool server".
#
# Why a single mcpo (vs. one systemd unit per MCP server):
#   * mcpo's own design already supervises child processes per entry in
#     its JSON config, so wrapping each one in its own unit duplicates
#     work and makes restarts noisier.
#   * Open WebUI registers mcpo as ONE base URL and discovers tool servers
#     by path — so everything sits behind one port with one firewall rule.
#   * If one MCP server crashes, mcpo restarts just that child; systemd
#     only needs to worry about mcpo itself.
#
# Packaging approach (mirrors `modules/nixos/vllm/default.nix`):
#   * `mcpo` is published on PyPI (`pip install mcpo`) but is NOT packaged
#     in nixpkgs. We install it into a uv-managed venv at first service
#     start, same pattern as vllm. The venv is pinned by version and
#     auto-recreated on version bumps.
#   * Child MCP servers launched via `npx` pull their package from the npm
#     registry on first invocation and cache into the user's XDG cache
#     (under `cfg.stateDir/.npm` so it's persistent across reboots).
#
# Usage:
#   local.mcpo = {
#     enable = true;
#     openFirewall = true;
#     servers = {
#       obsidian = {
#         command = "npx";
#         args = [
#           "-y"
#           "@bitbonsai/mcpvault@latest"
#           "/home/casazza/obsidian/vault"
#         ];
#         # @bitbonsai/mcpvault takes the vault path as a positional
#         # arg; no env vars needed.
#       };
#     };
#   };
#
# Verify:
#   curl http://luna.local:8100/obsidian/openapi.json | jq .info
#   # Browser: http://luna.local:8100/obsidian/docs (Swagger UI)
#
# Wire into Open WebUI:
#   Admin → Settings → Tools → Add tool server:
#     URL:  http://luna.local:8100/obsidian
#     Name: Obsidian
#   (No auth; mcpo inherits whatever network posture the firewall gives it.)
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.mcpo;

  serverOpts =
    { name, ... }:
    {
      options = {
        command = mkOption {
          type = types.str;
          example = "npx";
          description = ''
            Executable launched by mcpo for this MCP server. Must be
            resolvable on the systemd unit's PATH (which includes
            `pkgs.nodejs`, `pkgs.uv`, and anything in `cfg.extraPath`).
          '';
        };

        args = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "-y"
            "@bitbonsai/mcpvault@latest"
            "/home/casazza/obsidian/vault"
          ];
          description = "Positional arguments passed to `command`.";
        };

        env = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = literalExpression ''{ FOO = "bar"; }'';
          description = ''
            Environment variables exported ONLY to this MCP server child
            process (not to mcpo itself nor to other servers).
          '';
        };
      };
    };

  # mcpo reads a JSON config with the Claude-Desktop `mcpServers` schema.
  # Each entry: { command, args, env? }.
  mcpoConfig = {
    mcpServers = mapAttrs (
      _: svc:
      {
        inherit (svc) command args;
      }
      // optionalAttrs (svc.env != { }) { inherit (svc) env; }
    ) cfg.servers;
  };

  mcpoConfigFile = pkgs.writeText "mcpo-config.json" (builtins.toJSON mcpoConfig);

  # Bootstrap a uv-managed venv at first start, pip-install the pinned
  # mcpo version, stamp it, then exec. Idempotent across restarts;
  # version drift triggers a full venv rebuild (same pattern as vllm).
  startScript = pkgs.writeShellScript "mcpo-start" ''
    set -eu

    VENV="${cfg.venvDir}"
    MCPO_VERSION="${cfg.mcpoVersion}"
    VERSION_STAMP="$VENV/.mcpo-version"

    if [ -x "$VENV/bin/python" ] && [ -f "$VERSION_STAMP" ]; then
      installed_version="$(cat "$VERSION_STAMP")"
      if [ "$installed_version" != "$MCPO_VERSION" ]; then
        echo "mcpo: version changed ($installed_version → $MCPO_VERSION), recreating venv"
        rm -rf "$VENV"
      fi
    fi

    if [ ! -x "$VENV/bin/python" ]; then
      echo "mcpo: bootstrapping venv at $VENV"
      ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
    fi

    # uv pip install is a near-instant no-op when the version is already
    # satisfied, so we run it unconditionally to pick up bumps.
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
      --quiet \
      "mcpo==$MCPO_VERSION"

    echo "$MCPO_VERSION" > "$VERSION_STAMP"

    exec "$VENV/bin/mcpo" \
      --host "${cfg.host}" \
      --port "${toString cfg.port}" \
      --config "${mcpoConfigFile}"
  '';
in
{
  options.local.mcpo = {
    enable = mkEnableOption "MCP-to-OpenAPI proxy (Open WebUI tool bridge)";

    mcpoVersion = mkOption {
      type = types.str;
      default = "0.0.17";
      description = ''
        PyPI version of `mcpo` to install into the venv. Pin to a
        known-good release; bumping recreates the venv on next start.
        History: https://pypi.org/project/mcpo/#history
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = "Python interpreter the venv is built around.";
    };

    uv = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "uv binary used to bootstrap and update the venv.";
    };

    nodejs = mkOption {
      type = types.package;
      default = pkgs.nodejs;
      defaultText = literalExpression "pkgs.nodejs";
      description = ''
        Node.js used to provide `npx` for servers launched via
        `command = "npx"`. Most MCP servers (including
        @bitbonsai/mcpvault) distribute as npm packages.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Defaults to all interfaces so Open WebUI running
        on the same LAN can reach it. Set to `127.0.0.1` for
        loopback-only access.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8100;
      description = "HTTP port for the mcpo OpenAPI surface.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open `cfg.port` on the host firewall. Off by default — mcpo
        ships no authentication. Only flip on for LAN-trusted hosts
        (mirrors `local.vllm.openFirewall`).
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/mcpo";
      description = ''
        State directory for mcpo. Holds the venv (at `venvDir`), the
        npm cache for `npx`-launched MCP servers, and any per-server
        on-disk scratch. Survives nixos-rebuilds.
      '';
    };

    venvDir = mkOption {
      type = types.path;
      default = "/var/lib/mcpo/venv";
      description = ''
        Persistent uv venv location for mcpo itself. Wipe to force a
        fresh bootstrap.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "mcpo";
      description = "System user that runs mcpo.";
    };

    group = mkOption {
      type = types.str;
      default = "mcpo";
      description = "System group for mcpo.";
    };

    extraPath = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Extra packages placed on the systemd unit's PATH. Useful if a
        particular MCP server needs additional binaries (e.g. `git`
        for a git-aware MCP server, or `ripgrep` for search servers).
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Environment variables exported to the mcpo process itself and
        inherited by every child MCP server (unless overridden in the
        server's `env`). Use per-server `env` for scoped config.
      '';
    };

    servers = mkOption {
      type = types.attrsOf (types.submodule serverOpts);
      default = { };
      description = ''
        Map of server name → MCP server spec. The name becomes the
        URL path component — e.g. `servers.obsidian` is served at
        `http://<host>:<port>/obsidian`.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.servers != { };
        message = ''
          local.mcpo.enable = true but `local.mcpo.servers` is empty.
          Add at least one MCP server or leave the module disabled.
        '';
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
      description = "MCP-to-OpenAPI proxy";
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      # uv venv needs a writable parent; keep separate from stateDir in
      # case users relocate venvDir elsewhere.
      "d ${builtins.dirOf cfg.venvDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.mcpo = {
      description = "mcpo — MCP-to-OpenAPI proxy for Open WebUI";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # PATH so `npx`, `uvx`, `git`, etc. resolve for child MCP servers.
      path = [
        cfg.nodejs
        cfg.uv
        pkgs.coreutils
      ]
      ++ cfg.extraPath;

      environment = {
        HOME = cfg.stateDir;
        # Redirect npm's caches into stateDir so `npx -y obsidian-mcp-server`
        # doesn't try to write to /root/.npm or a user's $HOME.
        NPM_CONFIG_CACHE = "${cfg.stateDir}/.npm";
        XDG_CACHE_HOME = "${cfg.stateDir}/.cache";
      }
      // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;

        ExecStart = startScript;

        # First start pulls the mcpo wheel + any `npx -y` packages;
        # allow a generous window for cold caches.
        TimeoutStartSec = "10min";

        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = "10min";

        # Sandboxing. Read-only elsewhere; stateDir + venvDir writable
        # for the venv bootstrap and npm cache.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.stateDir
          cfg.venvDir
          (builtins.dirOf cfg.venvDir)
        ];
        # Obsidian MCP and similar file-backed servers need to READ the
        # user's vault. Individual server `args` (or `env`) point at
        # those paths, and ProtectHome = true hides /home/* — so we
        # explicitly un-hide via BindReadOnly by way of the caller
        # adding paths to
        # `systemd.services.mcpo.serviceConfig.BindReadOnlyPaths` in
        # their system config. (Kept empty-by-default here so the
        # module itself doesn't assume any host layout.)
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        # No GPU, no privileged syscalls — safe to restrict.
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };
  };
}
