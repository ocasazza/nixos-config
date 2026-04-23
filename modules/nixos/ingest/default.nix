# Declarative ingestion pipeline.
#
# Wires three pull-over-API source adapters (obsidian vault via the
# GitHub Contents API, Atlassian Cloud Jira+Confluence, and arbitrary
# GitHub repos) into one sink (Open WebUI Knowledge API) through
# LangGraph graphs defined in the ingest project (tracked declaratively
# under `projects/ingest/` in the nixos-config repo).
#
# Per-source wiring: one `systemd.services.ingest-<name>` oneshot +
# one `systemd.timers.ingest-<name>` (OnCalendar from `schedule`).
# No long-running watchers; no vault-on-disk dependency.
#
# Venv strategy: same pattern as modules/nixos/vllm/default.nix. On
# first service start, uv creates a venv under cfg.venvDir and
# pip-installs the project in editable mode from cfg.projectDir. A
# `.ingest-python-version` stamp triggers venv rebuild on python
# version bumps.
#
# Usage:
#   local.ingest = {
#     enable = true;
#     projectDir = "/home/casazza/ingest";
#
#     sinks.openwebui = {
#       url = "http://localhost:8080";
#       tokenFile = config.sops.secrets.openwebui-api-token.path;
#       knowledges = {
#         kb-it-tickets = "IT tickets pulled from Jira + GitHub issues";
#         # ...
#       };
#     };
#
#     sources = {
#       obsidian = { type = "obsidian"; enabled = true; schedule = "*:0/15"; };
#       atlassian = {
#         type = "atlassian"; enabled = true; schedule = "*:0/30";
#         baseUrl = "https://foo.atlassian.net";
#         emailFile = config.sops.secrets.atlassian-email.path;
#         tokenFile = config.sops.secrets.atlassian-api-token.path;
#         jiraProjects = [ "OPS" "IT" ];
#         confluenceSpaces = [ "IT" ];
#       };
#       github = {
#         type = "github"; enabled = true; schedule = "*:0/30";
#         tokenFile = config.sops.secrets.github-api-token.path;
#         repos = [
#           { slug = "ocasazza/nixos-config"; kind = "internal"; includeDocs = true; }
#         ];
#       };
#     };
#   };
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.ingest;

  # Defaults used below + documented in the option schema. Keep in sync
  # with DEFAULT_OBSIDIAN_FOLDER_MAP in ingest/config.py.
  defaultObsidianFolderMap = {
    "vault/10-Journal" = "kb-notes-personal";
    "vault/20-Research-Hub" = "kb-notes-personal";
    "vault/30-Knowledge-Base/IT-Ops" = "kb-it-docs";
    "vault/30-Knowledge-Base/Architecture" = "kb-systems-internal";
    "vault/30-Knowledge-Base/Hardware" = "kb-systems-external";
    "vault/30-Knowledge-Base/Tools-and-Links" = "kb-systems-external";
  };

  # Submodule describing one github repo entry.
  githubRepoOpts =
    { ... }:
    {
      options = {
        slug = mkOption {
          type = types.str;
          example = "ocasazza/nixos-config";
          description = "GitHub `owner/repo` slug.";
        };
        kind = mkOption {
          type = types.enum [
            "internal"
            "external"
          ];
          default = "internal";
          description = ''
            Steers the repo's docs into kb-systems-internal (internal) or
            kb-systems-external (external). Issues/PRs always land in the
            shared ticket bucket regardless of kind.
          '';
        };
        includeIssues = mkOption {
          type = types.bool;
          default = true;
          description = "Ingest issues from this repo.";
        };
        includePRs = mkOption {
          type = types.bool;
          default = true;
          description = "Ingest pull requests from this repo.";
        };
        includeDocs = mkOption {
          type = types.bool;
          default = true;
          description = "Ingest markdown docs (see docsPaths).";
        };
        docsPaths = mkOption {
          type = types.listOf types.str;
          default = [
            "docs"
            "README.md"
          ];
          description = ''
            Path prefixes inside the repo to treat as docs. Each entry
            is matched against each blob path via
            `path == prefix || path.startsWith(prefix + "/")`.
          '';
        };
      };
    };

  # Source submodule — one per named entry in cfg.sources.
  #
  # Fields are a superset across types. Irrelevant fields for a given
  # type are simply ignored by the adapter (NixOS can't cleanly
  # discriminate submodule shape off a type-tag without heavyweight
  # assertions, so we keep the schema flat and let the adapter's env
  # consumption be the source of truth).
  sourceOpts =
    { ... }:
    {
      options = {
        type = mkOption {
          type = types.enum [
            "obsidian"
            "atlassian"
            "github"
          ];
          description = "Adapter type — selects which systemd unit shape is rendered.";
        };

        enabled = mkOption {
          type = types.bool;
          default = true;
          description = "Render units for this source. Set false to temporarily disable.";
        };

        schedule = mkOption {
          type = types.str;
          default = "*:0/30";
          description = ''
            systemd OnCalendar expression for the timer.
            `*:0/30` = every 30 minutes; `*:0/15` = every 15.
          '';
        };

        # ── obsidian ─────────────────────────────────────────────────
        repo = mkOption {
          type = types.str;
          default = "ocasazza/obsidian";
          description = "(obsidian) GitHub slug of the vault repo.";
        };

        branch = mkOption {
          type = types.str;
          default = "main";
          description = "(obsidian) Branch to pull from.";
        };

        obsidianTokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            (obsidian) File containing a GitHub PAT with read access to
            `repo`. Leave null for a public repo.
          '';
        };

        folderMap = mkOption {
          type = types.attrsOf types.str;
          default = defaultObsidianFolderMap;
          description = ''
            (obsidian) Vault path prefix → Open WebUI knowledge name.
            Matches are longest-prefix-first. Paths outside every
            configured prefix are silently skipped.
          '';
        };

        # ── atlassian ────────────────────────────────────────────────
        baseUrl = mkOption {
          type = types.str;
          default = "";
          description = "(atlassian) Cloud base URL, e.g. https://foo.atlassian.net";
        };

        emailFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "(atlassian) File containing the account email.";
        };

        tokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "(atlassian / github) File containing the API token.";
        };

        jiraProjects = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "(atlassian) Jira project keys to sync. Empty = all accessible.";
        };

        confluenceSpaces = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "(atlassian) Confluence space keys to sync. Empty = all accessible.";
        };

        # ── github ───────────────────────────────────────────────────
        repos = mkOption {
          type = types.listOf (types.submodule githubRepoOpts);
          default = [ ];
          description = "(github) Repos to pull issues / PRs / docs from.";
        };
      };
    };

  sinkOpts = {
    options = {
      url = mkOption {
        type = types.str;
        default = "http://localhost:8080";
        description = "Open WebUI base URL.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          File containing the Open WebUI API token (generated in UI →
          Settings → Account). Use sops-nix / agenix.
        '';
      };

      knowledges = mkOption {
        type = types.attrsOf types.str;
        default = {
          kb-it-tickets = "IT tickets pulled from Jira + GitHub issues";
          kb-it-docs = "IT runbooks, Confluence, and vault IT-Ops notes";
          kb-notes-personal = "Personal notes, journal, research from vault";
          kb-notes-meetings = "Meeting transcripts and action items";
          kb-systems-internal = "Internal system design/config/maintenance docs";
          kb-systems-external = "External vendor/upstream docs";
        };
        description = "Knowledge name → description, seeded on first push.";
      };
    };
  };

  # Environment shared across every unit. Secrets are injected from
  # files *inside* the wrapper script, not as env vars here, so the
  # systemd journal never sees them.
  commonEnv = {
    INGEST_STATE_DIR = toString cfg.stateDir;
    INGEST_OPENWEBUI_URL = cfg.sinks.openwebui.url;
    INGEST_PHOENIX_ENDPOINT = cfg.phoenixEndpoint;
    INGEST_VENV = toString cfg.venvDir;
    PHOENIX_COLLECTOR_ENDPOINT = cfg.phoenixEndpoint;
    HOME = toString cfg.cacheDir;
  };

  # Venv bootstrap script — mirrors modules/nixos/vllm/default.nix.
  venvBootstrap = pkgs.writeShellScript "ingest-venv-bootstrap" ''
    set -eu

    VENV="${toString cfg.venvDir}"
    VERSION="${cfg.pythonVersion}"
    STAMP="$VENV/.ingest-python-version"

    if [ -x "$VENV/bin/python" ] && [ -f "$STAMP" ]; then
      installed="$(cat "$STAMP")"
      if [ "$installed" != "$VERSION" ]; then
        echo "ingest: python version changed ($installed → $VERSION), recreating venv"
        rm -rf "$VENV"
      fi
    fi

    if [ ! -x "$VENV/bin/python" ]; then
      echo "ingest: bootstrapping venv at $VENV"
      ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
    fi

    echo "ingest: syncing deps from ${toString cfg.projectDir}"
    ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" --quiet \
      --editable "${toString cfg.projectDir}"

    echo "$VERSION" > "$STAMP"
  '';

  # JSON-encoded obsidian folder map; consumed by config.py via a
  # pydantic JSON-parsing validator.
  obsidianFolderMapJSON = src: builtins.toJSON src.folderMap;

  # JSON blob of repos for the github adapter. config.py parses with a
  # pydantic validator; each entry's keys match GithubRepoSpec's.
  githubReposJSON =
    src:
    builtins.toJSON (
      map (r: {
        inherit (r) slug kind;
        includeIssues = r.includeIssues;
        includePRs = r.includePRs;
        includeDocs = r.includeDocs;
        docsPaths = r.docsPaths;
      }) src.repos
    );

  # Per-source ExecStart wrapper. The wrapper reads every secret file
  # into the environment at the last possible moment so secrets don't
  # leak into nix store paths or systemd's visible Environment.
  startScriptFor =
    name: src:
    let
      common = ''
        set -eu
        ${lib.optionalString (cfg.sinks.openwebui.tokenFile != null) ''
          export INGEST_OPENWEBUI_TOKEN="$(cat ${cfg.sinks.openwebui.tokenFile})"
        ''}
      '';
    in
    if src.type == "obsidian" then
      pkgs.writeShellScript "ingest-${name}-start" ''
        ${common}
        ${lib.optionalString (src.obsidianTokenFile != null) ''
          export INGEST_OBSIDIAN_TOKEN="$(cat ${src.obsidianTokenFile})"
        ''}
        export INGEST_OBSIDIAN_REPO="${src.repo}"
        export INGEST_OBSIDIAN_BRANCH="${src.branch}"
        export INGEST_OBSIDIAN_FOLDER_MAP='${obsidianFolderMapJSON src}'
        ${venvBootstrap}
        # Invoke bash explicitly: scripts use `#!/usr/bin/env bash` but the
        # systemd unit's PATH (coreutils + findutils + grep + sed + systemd)
        # has no bash, so `env bash` exits 127. See ingest-atlassian failure
        # mode 2026-04-23.
        exec ${pkgs.bash}/bin/bash ${toString cfg.projectDir}/scripts/obsidian-sync.sh
      ''
    else if src.type == "atlassian" then
      pkgs.writeShellScript "ingest-${name}-start" ''
        ${common}
        ${lib.optionalString (src.emailFile != null) ''
          export INGEST_ATLASSIAN_EMAIL="$(cat ${src.emailFile})"
        ''}
        ${lib.optionalString (src.tokenFile != null) ''
          export INGEST_ATLASSIAN_API_TOKEN="$(cat ${src.tokenFile})"
        ''}
        export INGEST_ATLASSIAN_BASE_URL="${src.baseUrl}"
        # Emit list-typed env vars as JSON arrays, not CSV — pydantic-settings'
        # EnvSettingsSource auto-parses complex (list/dict) typed fields as JSON
        # in `prepare_field_value`, which runs BEFORE any `mode="before"` field
        # validator. A CSV like "OPS,IT" or a bare word like "SYSMGR" raises
        # SettingsError before our `_parse_json_field` validator gets the chance
        # to do its CSV fallback. JSON arrays parse cleanly. (Empty list also
        # works — `[]` is valid JSON.) See ingest config.py validator.
        export INGEST_ATLASSIAN_JIRA_PROJECTS='${builtins.toJSON src.jiraProjects}'
        export INGEST_ATLASSIAN_CONFLUENCE_SPACES='${builtins.toJSON src.confluenceSpaces}'
        ${venvBootstrap}
        exec ${pkgs.bash}/bin/bash ${toString cfg.projectDir}/scripts/atlassian-sync.sh
      ''
    else
      # github
      pkgs.writeShellScript "ingest-${name}-start" ''
        ${common}
        ${lib.optionalString (src.tokenFile != null) ''
          export INGEST_GITHUB_TOKEN="$(cat ${src.tokenFile})"
        ''}
        export INGEST_GITHUB_REPOS='${githubReposJSON src}'
        ${venvBootstrap}
        exec ${pkgs.bash}/bin/bash ${toString cfg.projectDir}/scripts/github-sync.sh
      '';

  enabledSources = filterAttrs (_: s: s.enabled) cfg.sources;

in
{
  options.local.ingest = {
    enable = mkEnableOption "declarative knowledge ingestion";

    projectDir = mkOption {
      type = types.path;
      default = "/home/casazza/ingest";
      description = ''
        Filesystem path to the ~/ingest project checkout (contains
        pyproject.toml, langgraph.json, ingest/ package). The venv is
        pip-installed from here in editable mode.
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python312;
      defaultText = literalExpression "pkgs.python312";
      description = "Python interpreter the venv is built around.";
    };

    pythonVersion = mkOption {
      type = types.str;
      default = "3.12";
      description = "Stamped into the venv — used to detect version drift.";
    };

    uv = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "uv binary used to bootstrap and update the venv.";
    };

    venvDir = mkOption {
      type = types.path;
      default = "/var/lib/ingest/venv";
      description = "Persistent venv location.";
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/lib/ingest";
      description = "State dir root (venv lives under here, state.json alongside).";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/ingest";
      description = ''
        Where the sink caches knowledge IDs (state.json), external_id
        → file_id mappings, and per-source last-sync cursors.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "ingest";
      description = ''
        User that runs the ingest services. A dedicated system user —
        the pipeline is outbound-only and needs no special privileges.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "ingest";
      description = "Primary group for the ingest user.";
    };

    phoenixEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:6006/v1/traces";
      description = "Phoenix OTLP HTTP trace endpoint.";
    };

    sinks = mkOption {
      type = types.submodule {
        options.openwebui = mkOption {
          type = types.submodule sinkOpts;
          default = { };
          description = "Open WebUI Knowledge sink configuration.";
        };
      };
      default = { };
      description = "Sink configuration. Currently only Open WebUI.";
    };

    sources = mkOption {
      type = types.attrsOf (types.submodule sourceOpts);
      default = { };
      description = "Source adapters — one per named entry.";
    };
  };

  config = mkIf cfg.enable {
    # Dedicated, unprivileged system user. Outbound-only — no need for
    # wheel/network/etc. groups. TODO(ingest): if a future source ever
    # needs local vault access, migrate back to the `casazza` user;
    # until then keep the blast radius minimal.
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = toString cfg.cacheDir;
      createHome = true;
      description = "Declarative ingest pipeline";
    };

    systemd.tmpfiles.rules = [
      "d ${toString cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${toString cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${builtins.dirOf (toString cfg.venvDir)} 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Outbound-only — no firewall ports.

    # One oneshot service per enabled source.
    systemd.services = lib.mapAttrs' (
      name: src:
      lib.nameValuePair "ingest-${name}" {
        description = "Ingest: ${src.type} pull (${name})";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        environment = commonEnv;

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = toString cfg.projectDir;
          ExecStart = startScriptFor name src;

          TimeoutStartSec = "30min";

          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            (toString cfg.cacheDir)
            (toString cfg.venvDir)
            (toString cfg.stateDir)
          ];
          # The editable install writes .egg-info and __pycache__ under
          # projectDir — we need write access there for `uv pip install
          # --editable` to succeed on first bootstrap.
          BindPaths = [ (toString cfg.projectDir) ];
          PrivateTmp = true;
        };
      }
    ) enabledSources;

    # Matching timer per service.
    systemd.timers = lib.mapAttrs' (
      name: src:
      lib.nameValuePair "ingest-${name}" {
        description = "Ingest: ${src.type} timer (${name})";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = src.schedule;
          Persistent = true;
          Unit = "ingest-${name}.service";
        };
      }
    ) enabledSources;
  };
}
