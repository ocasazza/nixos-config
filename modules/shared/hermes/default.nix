{
  config,
  lib,
  pkgs,
  user,
  hermes,
  system,
  ...
}:

with lib;

let
  cfg = config.local.hermes;
  ollamaBaseUrl = "${cfg.ollamaHost}:${toString cfg.ollamaPort}/v1";
  exoBaseUrl = "http://localhost:${toString cfg.exo.apiPort}/v1";

  # When the LiteLLM path is active:
  #   * Auxiliary + cloud models route via `/vertex/v1` (LiteLLM
  #     passthrough forwards the gcloud id-token written into
  #     ~/.hermes/.env to vertex-proxy unchanged).
  #   * Delegation + local models route via `/v1` (LiteLLM's OpenAI-
  #     compat router), authenticated by the sops-minted virtual key
  #     read from virtualKeyFile at shell init.
  #
  # When LiteLLM is disabled, fall through to the legacy direct paths.
  vertexProxyBaseUrl =
    if cfg.litellm.enable then "${cfg.litellm.endpoint}/vertex/v1" else cfg.vertexProxy.baseURL;

  # The effective local base_url: LiteLLM's router takes priority over
  # exo takes priority over ollama when all are configured.
  localBaseUrl =
    if cfg.litellm.enable then
      "${cfg.litellm.endpoint}/v1"
    else if cfg.exo.enable then
      exoBaseUrl
    else
      ollamaBaseUrl;

  # Model name hermes uses for "local" completions. When LiteLLM is in
  # the path, hermes talks to LiteLLM's router by model-GROUP name, not
  # by the underlying model id — the group maps to the right backend in
  # desk-nxst-001's host config. Defaults to `local-coder` (burst-safe)
  # but host configs can override via `local.hermes.litellm.defaultLocalGroup`.
  localModelName = if cfg.litellm.enable then cfg.litellm.defaultLocalGroup else cfg.localModel;

  # api_key injected into hermes' generated config. LiteLLM's router
  # expects the virtual-key bearer; everything else keeps the legacy
  # "ollama" literal (vLLM ignores the value).
  # `$LITELLM_HERMES_API_KEY` (not `env:...`) is the literal placeholder
  # the activation-time sed replaces with the real sops-decrypted key
  # before hermes ever reads the file. Keeping a single placeholder form
  # keeps the substitution unambiguous.
  localApiKey = if cfg.litellm.enable then "$LITELLM_HERMES_API_KEY" else "ollama";
  # Helper: resolve interface names to libp2p listen multiaddrs at runtime
  exoListenAddrsScript = concatMapStringsSep "\n" (iface: ''
    _exo_addr=$(ipconfig getifaddr ${iface} 2>/dev/null || ip -4 addr show ${iface} 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -n "$_exo_addr" ] && _exo_listen_addrs="$_exo_listen_addrs /ip4/$_exo_addr/tcp/${toString cfg.exo.libp2pPort}"
  '') cfg.exo.listenInterfaces;

  # Wrapper script for the exo launchd service.
  # - auto: exec exo directly, let it handle discovery
  # - lan:  exec exo with EXO_LIBP2P_NAMESPACE for cluster isolation, no interface pinning
  # - thunderbolt: wait for P2P link IPs on raw en* interfaces, build EXO_BOOTSTRAP_PEERS
  #   from peer /30 IPs, then exec exo.
  #   All logic is gated on network = "thunderbolt" so it never runs on lan/auto configs.
  exoLaunchScript = pkgs.writeShellScript "exo-launch" (
    ''
      set -euo pipefail
    ''
    + (
      if cfg.exo.network == "thunderbolt" then
        let
          # Build bootstrap peers from P2P link IPs to each directly-connected peer
          tbPeerAddrs =
            if myLinks != [ ] then
              lib.concatStringsSep "," (
                map (link: "/ip4/${link.peerIp}/tcp/${toString cfg.exo.libp2pPort}") myLinks
              )
            else
              "";
          # Interfaces to check for readiness
          myIfaces = lib.unique (map (l: l.iface) myLinks);
          ifaceChecks = lib.concatMapStringsSep " " (iface: iface) myIfaces;
        in
        (
          if myLinks != [ ] then
            ''
              # ── Thunderbolt L3 mesh peer discovery ──────────────────────────────────
              # Wait for at least one P2P interface to have a 10.99.x.x IP
              READY=0
              for _i in $(seq 1 30); do
                for iface in ${ifaceChecks}; do
                  if ifconfig "$iface" 2>/dev/null | grep -q 'inet 10\.99\.'; then
                    READY=1
                    break 2
                  fi
                done
                sleep 1
              done

              if [ "$READY" -eq 0 ]; then
                echo "WARNING: no TB P2P interface has a 10.99.x.x IP — falling back to mDNS discovery" >&2
              else
                export EXO_BOOTSTRAP_PEERS="${tbPeerAddrs}"
              fi
            ''
          else
            ''
              # No TB links — rely on mDNS discovery
            ''
        )
        + ''
          export EXO_LIBP2P_NAMESPACE="${cfg.exo.libp2pNamespace}"
          # ────────────────────────────────────────────────────────────────────────
        ''
      else if cfg.exo.network == "lan" then
        ''
          export EXO_LIBP2P_NAMESPACE="${cfg.exo.libp2pNamespace}"
        ''
      else
        ''
          # auto: no interface pinning, no namespace override
        ''
    )
    + ''
      exec ${cfg.exo.package}/bin/exo \
        --api-port ${toString cfg.exo.apiPort} \
        --libp2p-port ${toString cfg.exo.libp2pPort} \
        ''${EXO_BOOTSTRAP_PEERS:+--bootstrap-peers "$EXO_BOOTSTRAP_PEERS"}
    ''
  );
  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];

  # ── Thunderbolt L3 mesh helpers ───────────────────────────────────────────
  # Each cable is a /30 point-to-point link.  No bridge0 — pure L3.
  # thunderboltLinks is passed from the flake via exo-cluster.nix.

  # All links where this host is an endpoint
  myLinks = lib.concatMap (
    link:
    if link.a.host == cfg.exo.thunderboltHostname then
      [
        {
          ip = "${link.subnet}.1";
          peerIp = "${link.subnet}.2";
          peerHost = link.b.host;
          iface = link.a.iface;
          subnet = link.subnet;
        }
      ]
    else if link.b.host == cfg.exo.thunderboltHostname then
      [
        {
          ip = "${link.subnet}.2";
          peerIp = "${link.subnet}.1";
          peerHost = link.a.host;
          iface = link.b.iface;
          subnet = link.subnet;
        }
      ]
    else
      [ ]
  ) cfg.exo.thunderboltLinks;

  # Subnets this host is directly connected to
  mySubnets = map (l: l.subnet) myLinks;

  # All subnets in the mesh
  allSubnets = lib.unique (map (link: link.subnet) cfg.exo.thunderboltLinks);

  # Subnets we need a route to (not directly connected)
  indirectSubnets = lib.filter (s: !(builtins.elem s mySubnets)) allSubnets;

  # For each indirect subnet, find a gateway (a directly-connected peer
  # that IS on that subnet).  Pick the first match.
  routesForHost = map (
    subnet:
    let
      # Find ANY link endpoint on the target subnet that is also our direct peer
      peerOnSubnet = lib.findFirst (
        myLink:
        builtins.any (
          tbLink:
          tbLink.subnet == subnet && (tbLink.a.host == myLink.peerHost || tbLink.b.host == myLink.peerHost)
        ) cfg.exo.thunderboltLinks
      ) null myLinks;
    in
    if peerOnSubnet != null then
      {
        inherit subnet;
        gateway = peerOnSubnet.peerIp;
      }
    else
      null
  ) indirectSubnets;

  # All TB cluster hosts except this one
  otherTbHosts = lib.filter (h: h != cfg.exo.thunderboltHostname) cfg.exo.thunderboltCluster;

  # All (subnet, ip) tuples that a given host has across thunderboltLinks
  hostIPsOnLinks =
    host:
    lib.concatMap (
      link:
      if link.a.host == host then
        [
          {
            subnet = link.subnet;
            ip = "${link.subnet}.1";
          }
        ]
      else if link.b.host == host then
        [
          {
            subnet = link.subnet;
            ip = "${link.subnet}.2";
          }
        ]
      else
        [ ]
    ) cfg.exo.thunderboltLinks;

  # Pick the canonical IP to publish for a peer host:
  #   - direct neighbor → use peer's IP on the link to us (no routing needed)
  #   - indirect (multi-hop) → first IP on any link; static route handles the
  #     forwarding via the relay
  canonicalIPFor =
    host:
    let
      candidates = hostIPsOnLinks host;
      direct = lib.findFirst (c: builtins.elem c.subnet mySubnets) null candidates;
    in
    if direct != null then
      direct.ip
    else if candidates != [ ] then
      (builtins.head candidates).ip
    else
      null;

  # /etc/hosts entries for every TB peer (direct or indirect via relay).
  # Iterating over thunderboltCluster (not myLinks) ensures every host in
  # the mesh is resolvable, even if reachable only via a static route.
  tbHostsEntries = lib.concatMap (
    host:
    let
      ip = canonicalIPFor host;
    in
    if ip != null then [ "${ip} ${host}.tb ${host}.thunderbolt" ] else [ ]
  ) otherTbHosts;

  # This host's own .tb entry (use the IP from the first link, sorted for stability)
  tbMyIP = if myLinks != [ ] then (builtins.head myLinks).ip else null;

  tbEnabled =
    cfg.exo.network == "thunderbolt"
    && cfg.exo.thunderboltLinks != [ ]
    && cfg.exo.thunderboltHostname != null
    && myLinks != [ ];

  # On Darwin, rebuild hermes venv from the fork source.
  # The fork (~/Repositories/schrodinger/hermes-agent, schrodinger branch) carries
  # all Schrodinger changes as proper commits — no patches needed here.
  #
  # Two wheel overrides are still required because uv.lock doesn't include
  # macOS ARM64 variants for these packages:
  #   - onnxruntime: missing macosx_14_0_arm64 wheel
  #   - cffi: 2.0.0 regresses callback thread-safety on macOS (segfault in
  #     CoreAudio callback); pinned to 1.17.1
  hermesVenvDarwin = pkgs.callPackage (
    {
      python311,
      lib,
      callPackage,
    }:
    let
      workspace = hermes.inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = hermes.outPath;
      };
      projectOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      onnxruntimeOverlay = _final: prev: {
        onnxruntime = prev.onnxruntime.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/60/69/6c40720201012c6af9aa7d4ecdd620e521bd806dc6269d636fdd5c5aeebe/onnxruntime-1.24.4-cp311-cp311-macosx_14_0_arm64.whl";
            hash = "sha256-C9/Ojppkl87FhKq0B7cb9pfaxeG3t5dK3FC/dTO9s6I=";
          };
        });
      };
      cffiOverlay = _final: prev: {
        cffi = prev.cffi.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/6c/f5/6c3a8efe5f503175aaddcbea6ad0d2c96dad6f5abb205750d1b3df44ef29/cffi-1.17.1-cp311-cp311-macosx_11_0_arm64.whl";
            hash = "sha256-MMXgy1rkk8BMi0KRblLKOAefGyNcL4rl9FJ7ljxAHK8=";
          };
        });
      };
      pythonSet =
        (callPackage hermes.inputs.pyproject-nix.build.packages {
          python = python311;
        }).overrideScope
          (
            lib.composeManyExtensions [
              hermes.inputs.pyproject-build-systems.overlays.default
              projectOverlay
              onnxruntimeOverlay
              cffiOverlay
            ]
          );
    in
    pythonSet.mkVirtualEnv "hermes-agent-env" {
      hermes-agent = [ "all" ];
    }
  ) { };

  # Repackage hermes from the Schrodinger fork with the rebuilt venv on Darwin.
  # pname includes -schrodinger for FleetDM build identification (ITHELP-46694).
  hermesPackageDarwin =
    let
      skillsSrc = "${hermes.outPath}/skills";

      # Runtime tools — base + skill-dependent
      runtimeDeps =
        with pkgs;
        [
          nodejs_20
          ripgrep
          git
          openssh
          ffmpeg
          jq
          curl
        ]
        ++ lib.optionals (builtins.elem "github" cfg.skills) [ gh ];
      runtimePath = lib.makeBinPath runtimeDeps;
    in
    pkgs.stdenv.mkDerivation {
      pname = "hermes-agent-schrodinger";
      version = "0.1.0";
      dontUnpack = true;
      dontBuild = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hermes-agent/skills $out/bin

        # Copy only the enabled skill categories from upstream
      ''
      + lib.concatMapStringsSep "\n" (cat: ''
        if [ -d "${skillsSrc}/${cat}" ]; then
          cp -r "${skillsSrc}/${cat}" "$out/share/hermes-agent/skills/${cat}"
        fi
      '') cfg.skills
      + lib.optionalString (cfg.extraSkillsDir != null) ''

        # Merge extra custom skills into the skills dir
        for dir in ${cfg.extraSkillsDir}/*/; do
          cat_name="$(basename "$dir")"
          if [ ! -d "$out/share/hermes-agent/skills/$cat_name" ]; then
            cp -r "$dir" "$out/share/hermes-agent/skills/$cat_name"
          else
            # Merge individual skills into existing category
            cp -rn "$dir"/* "$out/share/hermes-agent/skills/$cat_name/" 2>/dev/null || true
          fi
        done
      ''
      + ''

        ${lib.concatMapStringsSep "\n"
          (name: ''
            makeWrapper ${hermesVenvDarwin}/bin/${name} $out/bin/${name} \
              --suffix PATH : "${runtimePath}" \
              --set HERMES_BUNDLED_SKILLS $out/share/hermes-agent/skills
          '')
          [
            "hermes"
            "hermes-agent"
            "hermes-acp"
          ]
        }
        runHook postInstall
      '';
      meta = with lib; {
        description = "AI agent with advanced tool-calling capabilities";
        homepage = "https://github.com/NousResearch/hermes-agent";
        mainProgram = "hermes";
        license = licenses.mit;
        platforms = platforms.unix;
      };
    };

  # Claw3D: 3D virtual office frontend for Hermes
  claw3dSrc = pkgs.fetchFromGitHub {
    owner = "iamlukethedev";
    repo = "Claw3D";
    rev = "04efa31c4014566e4d16ec811f1793d71870c6f5";
    hash = "sha256-KR+JnYaJaM+JqXaz5cRUpuzImzBz80OJVTjbe7YZOk8=";
  };

  claw3dPackage = pkgs.buildNpmPackage {
    pname = "claw3d";
    version = "0.1.5";
    src = claw3dSrc;
    npmDepsHash = "sha256-lztITSxz9H1+H1Lbe+1yH+Z5oQKeYfRdbSnFgZZuq9U=";
    nodejs = pkgs.nodejs_20;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    buildPhase = ''
      runHook preBuild
      npx next build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/{lib/claw3d,bin}

      cp -r .next $out/lib/claw3d/
      cp -r server $out/lib/claw3d/
      cp -r public $out/lib/claw3d/
      cp -r node_modules $out/lib/claw3d/
      cp package.json $out/lib/claw3d/
      cp next.config.ts $out/lib/claw3d/
      cp .env.example $out/lib/claw3d/.env.example

      # Main wrapper: starts the production server
      # --chdir ensures Next.js finds .next/ and next.config.ts
      makeWrapper ${pkgs.nodejs_20}/bin/node $out/bin/claw3d \
        --add-flags "$out/lib/claw3d/server/index.js" \
        --set NODE_ENV production \
        --chdir "$out/lib/claw3d"

      # Hermes adapter wrapper
      makeWrapper ${pkgs.nodejs_20}/bin/node $out/bin/claw3d-hermes-adapter \
        --add-flags "$out/lib/claw3d/server/hermes-gateway-adapter.js"
      runHook postInstall
    '';

    meta = with lib; {
      description = "3D virtual office for AI agents";
      homepage = "https://github.com/iamlukethedev/Claw3D";
      license = licenses.mit;
      mainProgram = "claw3d";
    };
  };

  defaultPackage = if isDarwin then hermesPackageDarwin else hermes.packages.${system}.default;
in
{
  options.local.hermes = {
    enable = mkEnableOption "Hermes Agent TUI";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      description = "The Hermes Agent package to install";
    };

    skills = mkOption {
      type = types.listOf types.str;
      default = [
        "software-development"
        "autonomous-ai-agents"
        "github"
        "research"
        "productivity"
        "mcp"
        "note-taking"
      ];
      description = "Skill categories to include from upstream hermes bundled skills";
    };

    extraSkillsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a directory of additional custom skills.
        These are merged alongside the upstream bundled skills.
      '';
    };

    localModel = mkOption {
      type = types.str;
      default = "qwen3.5:latest";
      description = "Local LLM model name for Ollama (delegation + auxiliary)";
    };

    ollamaPort = mkOption {
      type = types.port;
      default = 11434;
      description = "Ollama server port";
    };

    ollamaHost = mkOption {
      type = types.str;
      default = "http://localhost";
      description = "Ollama server host";
    };

    extraOllamaModels = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Ollama models to preload";
    };

    vertexProxy = {
      baseURL = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.vertex.proxyBaseURL;
        description = ''
          Vertex AI proxy base URL (Anthropic SDK appends /v1/messages).
          When `local.hermes.litellm.enable = true` this value is
          ignored — cloud calls route through LiteLLM's `/vertex/v1`
          passthrough instead.
        '';
      };

      model = mkOption {
        type = types.str;
        default = lib.salt.ai.models.claudeSonnet;
        description = "Model to use via Vertex proxy";
      };
    };

    # ── LiteLLM-routed path ───────────────────────────────────────────
    # Route all hermes calls through the LiteLLM proxy on desk-nxst-001:
    #   - `vertexProxy.baseURL` references become `<endpoint>/vertex/v1`
    #     (passthrough — gcloud id-token still flows via the refresh_token
    #     shim into ~/.hermes/.env)
    #   - `localBaseUrl` (ollama/exo) becomes `<endpoint>/v1` with
    #     authentication via the sops-decrypted virtual key
    #
    # Mutually exclusive with the legacy path: `enable = true` on this
    # block overrides everything that would otherwise hit vertex-proxy
    # or localhost:52416 directly.
    litellm = {
      # Default-on: hermes routes through LiteLLM rather than hitting Vertex /
      # exo directly. The legacy direct path is still reachable by setting
      # `local.hermes.litellm.enable = false;`. When enabled but no
      # `virtualKeyFile` is wired, only the cloud passthrough (/vertex/v1)
      # works — local routing (/v1) needs the per-host sops-decrypted key.
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route Hermes through LiteLLM instead of direct providers";
      };

      endpoint = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.caddyEndpoint;
        description = ''
          LiteLLM base URL. Serves `/vertex/v1` (passthrough for cloud
          Claude) and `/v1` (OpenAI-compat router for local groups).

          Defaults to the Caddy-fronted FQDN path
          (`http://desk-nxst-001.schrodinger.com:8080/litellm`) so every
          fleet client routes through one auditable reverse proxy that
          aggregates the various upstream providers. Bare `:4000` is
          reachable inside the corp LAN but bypasses Caddy.
        '';
      };

      virtualKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to this client's LiteLLM virtual key file. Expected
          format: a single `LITELLM_HERMES_API_KEY=sk-...` line that
          the zsh shellInit sources at every new shell, so the value
          is exported as `$LITELLM_HERMES_API_KEY` for hermes' config
          file to pick up via its `env:LITELLM_HERMES_API_KEY` indirect
          reference.

          On desk-nxst-001 this is
          `config.sops.secrets.litellm-key-hermes.path`; on darwin
          it's the /run/secrets path once sops-nix is wired on darwin
          hosts.
        '';
      };

      defaultLocalGroup = mkOption {
        type = types.str;
        default = lib.salt.ai.providers.litellm.defaultLocalGroup;
        description = ''
          LiteLLM model-group name hermes refers to when picking a
          "local" model (delegation in non-vertex mode, auxiliary
          in non-vertex mode). Only option: local-coder (resolves to
          all self-hosted Qwen models; desk-nxst-001 vLLM primary,
          gfr exo cluster fallback).
        '';
      };
    };

    delegation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route subtasks to a dedicated subagent model";
      };

      model = mkOption {
        type = types.str;
        default = "claude-haiku-4-5";
        description = "Model to use for subagent delegation";
      };

      provider = mkOption {
        type = types.str;
        default = "anthropic";
        description = "Provider for subagent delegation (anthropic uses the Vertex proxy)";
      };

      useVertexProxy = mkOption {
        type = types.bool;
        default = true;
        description = "Route subagent delegation through the Vertex AI proxy (uses vertexProxy.baseURL)";
      };

      maxIterations = mkOption {
        type = types.int;
        default = 50;
        description = "Per-subagent iteration cap";
      };

      defaultToolsets = mkOption {
        type = types.listOf types.str;
        default = [
          "terminal"
          "file"
          "web"
        ];
        description = "Default toolsets available to subagents";
      };
    };

    auxiliary = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auxiliary model configuration for side tasks";
      };

      useVertexProxy = mkOption {
        type = types.bool;
        default = true;
        description = "Route auxiliary tasks (vision, web_extract, approval, etc.) through Vertex proxy with Haiku instead of local LLM";
      };

      model = mkOption {
        type = types.str;
        default = "claude-haiku-4-5";
        description = "Model for auxiliary tasks when useVertexProxy is true";
      };
    };

    agent = {
      maxTurns = mkOption {
        type = types.int;
        default = 90;
        description = "Maximum tool-calling iterations per conversation";
      };

      reasoningEffort = mkOption {
        type = types.str;
        default = "";
        description = "Reasoning effort level: empty (medium), xhigh, high, medium, low, minimal, none";
      };

      gatewayTimeout = mkOption {
        type = types.int;
        default = 1800;
        description = "Gateway agent inactivity timeout in seconds (0 = unlimited)";
      };
    };

    compression = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic context compression when nearing model context limit";
      };

      threshold = mkOption {
        type = types.str;
        default = "0.70";
        description = "Compress when prompt tokens reach this ratio of the model context window";
      };

      protectLastN = mkOption {
        type = types.int;
        default = 20;
        description = "Always keep at least this many recent messages uncompressed";
      };

      summaryModel = mkOption {
        type = types.str;
        # Use the local LiteLLM-routed Qwen model for compression — never
        # cloud/vertex. Provider prefix matches the `litellm` custom_provider
        # declared in the generated config.yaml below.
        default = "litellm/local-coder";
        description = "Model used for compression summarisation (should be fast/cheap). Use a local model to avoid cloud egress.";
      };
    };

    display = {
      streaming = mkOption {
        type = types.bool;
        default = true;
        description = "Stream tokens to the terminal as they arrive";
      };

      showCost = mkOption {
        type = types.bool;
        default = true;
        description = "Show estimated cost in the CLI status bar";
      };

      bellOnComplete = mkOption {
        type = types.bool;
        default = true;
        description = "Play terminal bell when the agent finishes a task";
      };

      showReasoning = mkOption {
        type = types.bool;
        default = false;
        description = "Show model reasoning/thinking blocks above each response";
      };

      toolProgress = mkOption {
        type = types.enum [
          "off"
          "new"
          "all"
          "verbose"
        ];
        default = "all";
        description = "Tool call progress verbosity: off, new, all, verbose";
      };
    };

    approvals = {
      mode = mkOption {
        type = types.enum [
          "manual"
          "smart"
          "off"
        ];
        default = "smart";
        description = "Dangerous command approval mode: manual, smart (auto-approve low-risk), off";
      };
    };

    fileReadMaxChars = mkOption {
      type = types.int;
      default = 200000;
      description = "Maximum characters per read_file call — increase for large-context models like Claude";
    };

    memoryCharLimit = mkOption {
      type = types.int;
      default = 2200;
      description = "Maximum characters per memory entry";
    };

    userCharLimit = mkOption {
      type = types.int;
      default = 1375;
      description = "Maximum characters per user profile entry";
    };

    soulMd = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Content for ~/.hermes/SOUL.md — global agent identity injected into every session
        regardless of working directory (slot #1 in system prompt, before project context).
        Leave empty to keep the built-in Hermes default.
      '';
    };

    exo = {
      enable = mkEnableOption "exo distributed inference cluster (alternative to Ollama)";

      package = mkOption {
        type = types.package;
        default = pkgs.exo;
        defaultText = "pkgs.exo";
        description = "The exo package to use.";
      };

      apiPort = mkOption {
        type = types.port;
        default = 52415;
        description = "Port for the exo OpenAI-compatible API (used as the local base_url for hermes delegation).";
      };

      libp2pPort = mkOption {
        type = types.port;
        default = 52416;
        description = "Fixed TCP port for libp2p peer discovery. 0 lets the OS assign one.";
      };

      peers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "mac-studio.local:52416"
          "192.168.1.42:52416"
        ];
        description = ''
          Bootstrap peers to dial on startup, as hostname:port or libp2p multiaddr strings.
          Passed as a comma-separated list to --bootstrap-peers / EXO_BOOTSTRAP_PEERS.
        '';
      };

      listenInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "en0"
          "eth0"
        ];
        description = ''
          Network interfaces exo should advertise and listen on.
          Each interface name is resolved to its IPv4 address at service startup
          and added as a libp2p listen/announce multiaddr via EXO_LISTEN_ADDRS.
          Leave empty to let exo auto-detect.
        '';
      };

      network = mkOption {
        type = types.enum [
          "auto"
          "lan"
          "thunderbolt"
        ];
        default = "auto";
        description = ''
          Network transport for exo cluster communication.

          - auto:        Let exo auto-detect all interfaces. No namespace isolation.
          - lan:         WiFi/Ethernet. Sets EXO_LIBP2P_NAMESPACE for cluster
                         isolation but does not pin to specific interfaces.
          - thunderbolt: Thunderbolt Bridge (bridge0) only. At service startup the
                         wrapper script waits for bridge0 to acquire its IPv6
                         link-local address, seeds NDP via all-nodes multicast
                         (ff02::1%bridge0), reads back discovered peer fe80::
                         addresses, and sets EXO_BOOTSTRAP_PEERS accordingly.
                         Also sets EXO_LIBP2P_NAMESPACE for cluster isolation.
                         This logic is strictly gated on network = "thunderbolt"
                         and never runs on lan or auto configs.

          All cluster nodes must use the same network value.
        '';
      };

      thunderboltHostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          This machine's hostname within the Thunderbolt cluster.
          Must match one of the keys in thunderboltCluster.
          Passed via specialArgs from the flake (derived from thunderboltLinks).
        '';
      };

      thunderboltCluster = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Hostnames of all machines in the Thunderbolt cluster.
          Used for exo peer discovery.  The actual IP assignment
          comes from thunderboltLinks, not from sorted position.
        '';
      };

      thunderboltLinks = mkOption {
        type = types.listOf (types.attrsOf types.anything);
        default = [ ];
        example = [
          {
            subnet = "10.99.1";
            a = {
              host = "GN9CFLM92K-MBP";
              iface = "en1";
            };
            b = {
              host = "GJHC5VVN49-MBP";
              iface = "en2";
            };
          }
        ];
        description = ''
          Point-to-point Thunderbolt cable definitions.
          Each entry describes a /30 subnet between two endpoints.
          Side "a" gets .1, side "b" gets .2.  No L2 bridging — pure L3.

          The activation script:
          - Removes all en* interfaces from bridge0
          - Assigns /30 IPs to the raw en* interfaces
          - Adds static routes for non-directly-connected /30 subnets
          - Writes /etc/hosts with .tb hostnames → peer P2P IPs
          - Sets MTU 9000 (jumbo frames) on all TB interfaces

          Only takes effect when network = "thunderbolt".
        '';
      };

      libp2pNamespace = mkOption {
        type = types.str;
        default =
          if cfg.exo.network == "thunderbolt" then
            "schrodinger-tb"
          else if cfg.exo.network == "lan" then
            "schrodinger-lan"
          else
            "";
        defaultText = ''
          "schrodinger-tb"  when network = "thunderbolt"
          "schrodinger-lan" when network = "lan"
          ""                when network = "auto"
        '';
        description = ''
          EXO_LIBP2P_NAMESPACE value for cluster isolation.
          Prevents accidental peering with other exo clusters on the same network.
          Derived automatically from network but can be overridden.
          Only set in the environment when non-empty.
        '';
      };

      litellmTunnel = {
        enable = mkEnableOption ''
          Persistent reverse SSH tunnel from this Mac to a remote
          LiteLLM host, exposing the local exo API as `127.0.0.1:apiPort`
          on the remote so LiteLLM can route to it as a model deployment.

          Self-gated to the relay node (myLinks > 1) inside the tb mesh —
          the relay is the only node guaranteed to see the whole sharded
          cluster, so a single tunnel covers all 3 mesh nodes. CK2/L75
          set this option but emit no daemon
        '';

        remoteHost = mkOption {
          type = types.str;
          default = "desk-nxst-001.schrodinger.com";
          description = ''
            Hostname of the LiteLLM box that terminates the reverse tunnel.
            Use the FQDN: corp DNS (via AppGate) doesn't serve a short
            name, and relay nodes don't share GN9's per-user SSH alias.
          '';
        };

        remoteUser = mkOption {
          type = types.str;
          default = "exo-tunnel";
          description = ''
            Account on `remoteHost` that accepts the reverse tunnel.
            Convention: a dedicated system user whose authorized_keys
            entry is locked to a single forced-command + permitlisten
            for `127.0.0.1:apiPort`. See nixstation's host config.
          '';
        };

        identityFile = mkOption {
          type = types.path;
          default = "/etc/ssh/ssh_host_ed25519_key";
          description = ''
            SSH private key the LaunchDaemon authenticates with. Defaults
            to the host key (already present, identifies the Mac).
            Its public counterpart must be in `remoteUser`'s
            authorized_keys on `remoteHost`.
          '';
        };
      };
    };

    voice = {
      enable = mkEnableOption "Hermes CLI voice mode (microphone input + TTS output)";

      recordKey = mkOption {
        type = types.str;
        default = "ctrl+b";
        description = "Key binding to start/stop voice recording in the TUI";
      };

      autoTts = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically enable TTS when voice mode starts";
      };

      silenceThreshold = mkOption {
        type = types.int;
        default = 200;
        description = "RMS level (0-32767) below which audio counts as silence";
      };

      silenceDuration = mkOption {
        type = types.float;
        default = 3.0;
        description = "Seconds of silence before recording auto-stops";
      };

      sttProvider = mkOption {
        type = types.enum [
          "local"
          "groq"
          "openai"
        ];
        default = "local";
        description = "Speech-to-text provider. 'local' uses faster-whisper with no API key";
      };

      sttModel = mkOption {
        type = types.str;
        default = "base";
        description = "Whisper model for local STT (tiny, base, small, medium, large-v3)";
      };

      ttsProvider = mkOption {
        type = types.enum [
          "edge"
          "elevenlabs"
          "openai"
          "neutts"
        ];
        default = "edge";
        description = "Text-to-speech provider. 'edge' is free with no API key";
      };

      ttsVoice = mkOption {
        type = types.str;
        default = "en-US-AriaNeural";
        description = "Voice name for Edge TTS (ignored for other providers)";
      };
    };

    claw3d = {
      enable = mkEnableOption "Claw3D 3D virtual office for Hermes agents";

      package = mkOption {
        type = types.package;
        default = claw3dPackage;
        description = "The Claw3D package to install";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Port for the Claw3D web UI";
      };

      adapterPort = mkOption {
        type = types.port;
        default = 18789;
        description = "Port for the Hermes gateway adapter WebSocket";
      };

      hermesApiUrl = mkOption {
        type = types.str;
        default = "http://localhost:8642";
        description = "URL of the Hermes HTTP API";
      };

      gatewayToken = mkOption {
        type = types.str;
        default = "38d4b172b788b7ab72f8c7cd0196ce38fdfca0c46623916442428380d5a9fff1";
        description = "Shared secret token for gateway authentication between studio, adapter, and browser";
      };
    };

  };

  config = mkIf cfg.enable (mkMerge [
    # Common config: package, config file, shell init
    {
      environment.systemPackages = [ cfg.package ];

      # `force = true`: at activation, the home.activation.hermesConfigInjectKey
      # script (defined below) replaces this symlink with a real, key-injected
      # file. On the next activation HM would normally try to back up the
      # real file to `.bak` before placing a fresh symlink — and barf if the
      # `.bak` from the prior activation is still around. Force-overwrite
      # skips both the backup and the collision.
      home-manager.users.${user.name}.home.file.".hermes/config.yaml" = {
        force = true;
        text = concatStringsSep "\n" (
          (
            if cfg.litellm.enable then
              [
                "# Main model: Qwen3-Coder via LiteLLM smart-routed across the"
                "# desk-nxst-001 + desk-nxst-004 GPU pool. Bare `qwen` is an"
                "# alias on the LiteLLM side that rewrites to local-coder."
                "# To use cloud Claude instead, pick the `vertex` custom_provider"
                "# below or `litellm/coder-cloud-claude` (when re-enabled)."
                "model:"
                "  default: \"qwen\""
                "  provider: \"litellm\""
                "  base_url: \"${cfg.litellm.endpoint}/v1\""
                "  api_key: \"$LITELLM_HERMES_API_KEY\""
                ""
              ]
            else
              [
                "# Main model: cloud Claude direct to vertex-proxy (legacy path,"
                "# active because local.hermes.litellm.enable = false)"
                "model:"
                "  default: \"${cfg.vertexProxy.model}\""
                "  provider: \"anthropic\""
                "  base_url: \"${vertexProxyBaseUrl}\""
                ""
              ]
          )
          ++ [
            "# Custom OpenAI-compatible providers — pick any of these via"
            "# `/model <provider>/<model>` in the hermes TUI. The main `model:`"
            "# block above selects the default."
            "custom_providers:"
          ]
          ++ optionals cfg.litellm.enable [
            "  # LiteLLM router on desk-nxst-001:4000. The model names below"
            "  # are the real router groups + the alias names registered via"
            "  # `routerSettings.modelGroupAlias` on the proxy side. All qwen*"
            "  # aliases route to local-coder (Qwen3-Coder smart-routed across"
            "  # desk-nxst-001 + desk-nxst-004 vLLMs, exo nodes, laptop)."
            "  - name: \"litellm\""
            "    base_url: \"${cfg.litellm.endpoint}/v1\""
            "    api_key: \"$LITELLM_HERMES_API_KEY\""
            "    models:"
            "      - \"qwen\""
            "      - \"qwen-coder\""
            "      - \"qwen3-coder\""
            "      - \"Qwen3-Coder-30B\""
            "      - \"local-coder\""
            "      - \"embedding\""
            "      # Individual backend aliases (for direct pinning):"
            "      - \"desk-nxst-001-llama-3.3-70b\""
            "      - \"desk-nxst-004-qwen3-coder\""
            "      - \"gfr-osx26-02-qwen3-coder\""
            "      - \"gfr-osx26-03-qwen3-coder\""
            "      - \"laptop-qwen3-coder\""
          ]
          ++ optionals (cfg.exo.enable && !cfg.litellm.enable) [
            "  # exo distributed inference cluster (only when LiteLLM is disabled)"
            "  - name: \"exo\""
            "    base_url: \"${exoBaseUrl}\""
            "    api_key: \"ollama\""
            "    models:"
            "      - \"${cfg.localModel}\""
          ]
          ++ [
            "  # oMLX local inference server (Apple Silicon MLX). Same endpoint"
            "  # as opencode's provider.omlx — see modules/darwin/opencode/."
            "  - name: \"omlx\""
            "    base_url: \"http://localhost:8000/v1\""
            "    api_key: \"ollama-not-needed\""
            "    models:"
            "      - \"qwen3-coder-next\""
            "  # Schrodinger Azure OpenAI — same resource (schrodinger-code) and"
            "  # deployment (Kimi-K2.6) as opencode's provider.azure. The"
            "  # AZURE_API_KEY env var is sops-decrypted and exported by"
            "  # modules/darwin/opencode/default.nix's home.sessionVariablesExtra."
            "  - name: \"azure\""
            "    base_url: \"https://schrodinger-code.openai.azure.com/openai/deployments/Kimi-K2.6\""
            "    api_key: \"env:AZURE_API_KEY\""
            "    models:"
            "      - \"Kimi-K2.6\""
            "  # Direct Vertex AI proxy — same backend claude-code uses. Kept as"
            "  # a separately addressable provider so a hermes session can target"
            "  # Vertex directly when the LiteLLM proxy is unreachable or you"
            "  # specifically want to bypass the routing layer (apples-to-apples"
            "  # against claude-code's pathing). Auth is the same gcloud id-token"
            "  # that `apiKeyHelper` mints for claude-code."
            "  - name: \"vertex\""
            "    base_url: \"${cfg.vertexProxy.baseURL}\""
            "    api_key: \"env:GCLOUD_ID_TOKEN\""
            "    models:"
            "      - \"${cfg.vertexProxy.model}\""
            "  # Gemini via the same Vertex AI proxy. Uses the Vertex REST API"
            "  # format (publishers/google/models/...) — the proxy routes both"
            "  # Anthropic and Google publishers. Same gcloud id-token auth."
            "  - name: \"gemini\""
            "    base_url: \"${cfg.vertexProxy.baseURL}\""
            "    api_key: \"env:GCLOUD_ID_TOKEN\""
            "    models:"
            "      - \"${lib.salt.ai.models.gemini3Pro}\""
            "      - \"${lib.salt.ai.models.gemini3Flash}\""
            "      - \"${lib.salt.ai.models.gemini25Pro}\""
            "      - \"${lib.salt.ai.models.gemini25Flash}\""
            ""
          ]
          ++ optionals cfg.delegation.enable (
            if cfg.delegation.useVertexProxy then
              [
                "# Subagent delegation: Haiku via Vertex proxy (fast + cheap)"
                "delegation:"
                "  model: \"${cfg.delegation.model}\""
                "  provider: \"${cfg.delegation.provider}\""
                "  base_url: \"${vertexProxyBaseUrl}\""
                "  max_iterations: ${toString cfg.delegation.maxIterations}"
                "  default_toolsets: [${
                    concatStringsSep ", " (map (t: "\"${t}\"") cfg.delegation.defaultToolsets)
                  }]"
                ""
              ]
            else
              [
                "# Subagent delegation: local LLM (LiteLLM router when enabled)"
                "delegation:"
                "  base_url: \"${localBaseUrl}\""
                "  model: \"${localModelName}\""
                "  api_key: \"${localApiKey}\""
                "  max_iterations: ${toString cfg.delegation.maxIterations}"
                "  default_toolsets: [${
                    concatStringsSep ", " (map (t: "\"${t}\"") cfg.delegation.defaultToolsets)
                  }]"
                ""
              ]
          )
          ++ optionals cfg.auxiliary.enable (
            if cfg.auxiliary.useVertexProxy then
              [
                "# Auxiliary tasks: Haiku via Vertex proxy (vision, web, approval, memory)"
                "auxiliary:"
                "  vision:"
                "    provider: \"${cfg.delegation.provider}\""
                "    model: \"${cfg.auxiliary.model}\""
                "    base_url: \"${vertexProxyBaseUrl}\""
                "    timeout: 60"
                "    download_timeout: 30"
                "  web_extract:"
                "    provider: \"${cfg.delegation.provider}\""
                "    model: \"${cfg.auxiliary.model}\""
                "    base_url: \"${vertexProxyBaseUrl}\""
                "    timeout: 120"
                "  approval:"
                "    provider: \"${cfg.delegation.provider}\""
                "    model: \"${cfg.auxiliary.model}\""
                "    base_url: \"${vertexProxyBaseUrl}\""
                "    timeout: 30"
                "  session_search:"
                "    provider: \"${cfg.delegation.provider}\""
                "    model: \"${cfg.auxiliary.model}\""
                "    base_url: \"${vertexProxyBaseUrl}\""
                "    timeout: 30"
                "  flush_memories:"
                "    provider: \"${cfg.delegation.provider}\""
                "    model: \"${cfg.auxiliary.model}\""
                "    base_url: \"${vertexProxyBaseUrl}\""
                "    timeout: 60"
                "  compression:"
                "    timeout: 120"
                ""
              ]
            else
              [
                "# Auxiliary tasks: local LLM (LiteLLM router when enabled)"
                "auxiliary:"
                "  vision:"
                "    base_url: \"${localBaseUrl}\""
                "    model: \"${localModelName}\""
                "    api_key: \"${localApiKey}\""
                "  web_extract:"
                "    base_url: \"${localBaseUrl}\""
                "    model: \"${localModelName}\""
                "    api_key: \"${localApiKey}\""
                "  compression:"
                "    timeout: 120"
                ""
              ]
          )
          ++ optionals cfg.compression.enable [
            "# Context compression: Haiku for fast cheap summaries"
            "compression:"
            "  enabled: true"
            "  threshold: ${cfg.compression.threshold}"
            "  target_ratio: 0.25"
            "  protect_last_n: ${toString cfg.compression.protectLastN}"
            "  summary_model: \"${cfg.compression.summaryModel}\""
            "  summary_provider: \"${cfg.delegation.provider}\""
            "  summary_base_url: \"${vertexProxyBaseUrl}\""
            ""
          ]
          ++ optionals cfg.voice.enable [
            "# Voice mode: microphone input + TTS output"
            "voice:"
            "  record_key: \"${cfg.voice.recordKey}\""
            "  auto_tts: ${if cfg.voice.autoTts then "true" else "false"}"
            "  silence_threshold: ${toString cfg.voice.silenceThreshold}"
            "  silence_duration: ${toString cfg.voice.silenceDuration}"
            ""
            "stt:"
            "  provider: \"${cfg.voice.sttProvider}\""
            "  local:"
            "    model: \"${cfg.voice.sttModel}\""
            ""
            "tts:"
            "  provider: \"${cfg.voice.ttsProvider}\""
            "  edge:"
            "    voice: \"${cfg.voice.ttsVoice}\""
            ""
          ]
          ++ [
            "agent:"
            "  tool_use_enforcement: \"auto\""
            "  max_turns: ${toString cfg.agent.maxTurns}"
            "  gateway_timeout: ${toString cfg.agent.gatewayTimeout}"
          ]
          ++ optionals (cfg.agent.reasoningEffort != "") [
            "  reasoning_effort: \"${cfg.agent.reasoningEffort}\""
          ]
          ++ [
            ""
            "terminal:"
            "  backend: local"
            "  persistent_shell: true"
            "  timeout: 180"
            ""
            "memory:"
            "  provider: \"holographic\""
            "  memory_enabled: true"
            "  user_profile_enabled: true"
            "  memory_char_limit: ${toString cfg.memoryCharLimit}"
            "  user_char_limit: ${toString cfg.userCharLimit}"
            "  nudge_interval: 10"
            "  flush_min_turns: 6"
            ""
            "# Holographic memory plugin: HRR-backed compositional recall over a"
            "# local SQLite store. auto_extract pulls facts from the conversation"
            "# without requiring explicit `memory.record` calls."
            "plugins:"
            "  hermes-memory-store:"
            "    db_path: \"/Users/${user.name}/.hermes/memory_store.db\""
            "    auto_extract: true"
            ""
            "skills:"
            "  creation_nudge_interval: 15"
            ""
            "checkpoints:"
            "  enabled: true"
            "  max_snapshots: 50"
            ""
            "approvals:"
            "  mode: \"${cfg.approvals.mode}\""
            ""
            "display:"
            "  streaming: ${if cfg.display.streaming then "true" else "false"}"
            "  show_cost: ${if cfg.display.showCost then "true" else "false"}"
            "  bell_on_complete: ${if cfg.display.bellOnComplete then "true" else "false"}"
            "  show_reasoning: ${if cfg.display.showReasoning then "true" else "false"}"
            "  tool_progress: \"${cfg.display.toolProgress}\""
            "  inline_diffs: true"
            ""
            "security:"
            "  redact_secrets: true"
            "  tirith_enabled: false"
            ""
            "file_read_max_chars: ${toString cfg.fileReadMaxChars}"
          ]
        );
      };

      programs.zsh.shellInit = mkAfter (
        ''
          # Hermes Agent: Vertex proxy env vars and auth
          export ANTHROPIC_VERTEX_PROJECT_ID="${lib.salt.ai.providers.vertex.projectId}"
          export CLOUD_ML_REGION="${lib.salt.ai.providers.vertex.region}"

          # faster-whisper model is already cached locally; suppress the
          # huggingface_hub unauthenticated-request warning at transcription time.
          export HF_HUB_OFFLINE=1

          # Refresh hermes token using the same get-iam-token.sh helper as Claude Code.
          # Called as a shell function so it runs fresh on every `hermes` invocation.
          # When LiteLLM's cloud passthrough is in the path, this same id-token
          # is what LiteLLM forwards to vertex-proxy — no change to the refresh
          # contract needed.
          _hermes_refresh_token() {
            local _tok=""
            if [ -f "$HOME/.claude/get-iam-token.sh" ]; then
              _tok="$($HOME/.claude/get-iam-token.sh 2>/dev/null || echo "")"
            elif command -v gcloud >/dev/null 2>&1; then
              _tok="$(gcloud auth print-identity-token 2>/dev/null || echo "")"
            fi
            if [ -n "$_tok" ]; then
              mkdir -p "$HOME/.hermes"
              echo "ANTHROPIC_API_KEY=$_tok" > "$HOME/.hermes/.env"
            fi
          }

          # Wrap hermes binaries to refresh token before each run
          hermes() { _hermes_refresh_token; command hermes "$@"; }
          hermes-agent() { _hermes_refresh_token; command hermes-agent "$@"; }
          hermes-acp() { _hermes_refresh_token; command hermes-acp "$@"; }
        ''
        + optionalString (cfg.litellm.enable && cfg.litellm.virtualKeyFile != null) ''
          # Export the LiteLLM virtual key for ad-hoc shell use (curl,
          # debugging). The hermes config.yaml itself gets the key
          # baked in at activation time — see `home.activation
          # .hermesConfigInjectKey` below — so the daemon doesn't
          # depend on this env var being set.
          if [ -r "${toString cfg.litellm.virtualKeyFile}" ]; then
            export LITELLM_HERMES_API_KEY="$(cut -d= -f2- < "${toString cfg.litellm.virtualKeyFile}")"
          fi
        ''
      );

    }

    # One-shot at activation: render ~/.hermes/config.yaml from the
    # nix-store template with the sops-decrypted LITELLM virtual key
    # spliced in. Replaces the previous per-shell sed approach, which
    # had three problems: (1) BSD-vs-GNU sed-i incompatibility on macOS,
    # (2) raced when hermes was launched outside an interactive shell
    # (launchd, cron), (3) ran on every shell open for a one-shot op.
    #
    # Lives in its own mkMerge block so it doesn't collide with the
    # `home-manager.users.<u>.home.file.".hermes/config.yaml".text`
    # attribute defined above (Nix attribute paths can't repeat at
    # the same nesting level within a single attrset literal).
    (mkIf (cfg.litellm.enable && cfg.litellm.virtualKeyFile != null) {
      # Use the function form so `lib.hm.dag` (home-manager's extension
      # namespace) is in scope. The outer nix-darwin lib doesn't have it.
      home-manager.users.${user.name} =
        { lib, ... }:
        {
          home.activation.hermesConfigInjectKey = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            if [ -r "${toString cfg.litellm.virtualKeyFile}" ] \
                && [ -L "$HOME/.hermes/config.yaml" ]; then
              KEY="$(cut -d= -f2- < "${toString cfg.litellm.virtualKeyFile}")"
              TEMPLATE="$(readlink "$HOME/.hermes/config.yaml")"
              # Replace the symlink with a real, key-injected file.
              # Writing to a tmp file + mv keeps the swap atomic.
              run sed "s|\$LITELLM_HERMES_API_KEY|$KEY|g" "$TEMPLATE" \
                > "$HOME/.hermes/config.yaml.new"
              run mv -f "$HOME/.hermes/config.yaml.new" "$HOME/.hermes/config.yaml"
              run chmod 0400 "$HOME/.hermes/config.yaml"
            fi
          '';
        };
    })

    # SOUL.md: global agent identity (only written when soulMd option is set)
    (mkIf (cfg.soulMd != "") {
      home-manager.users.${user.name}.home.file.".hermes/SOUL.md".text = cfg.soulMd;
    })

    # NixOS (Linux): Ollama as a systemd service
    (optionalAttrs isLinux {
      services.ollama = {
        enable = true;
        port = cfg.ollamaPort;
        loadModels = [ cfg.localModel ] ++ cfg.extraOllamaModels;
      };
    })

    # NixOS (Linux): portaudio for CLI voice mode microphone input
    (optionalAttrs isLinux (
      mkIf cfg.voice.enable {
        environment.systemPackages = [ pkgs.portaudio ];
      }
    ))

    # Darwin (macOS): Ollama via Homebrew cask (launchd-managed)
    (mkIf (isDarwin && !cfg.exo.enable) {
      homebrew.casks = [ "ollama" ];
    })

    # Darwin (macOS): portaudio for CLI voice mode microphone input
    (optionalAttrs isDarwin (
      mkIf cfg.voice.enable {
        homebrew.brews = [ "portaudio" ];
      }
    ))

    # Thunderbolt L3 mesh: /30 P2P IPs on raw en* + static routes + /etc/hosts
    (mkIf (cfg.exo.enable && tbEnabled) {
      system.activationScripts.postActivation.text = lib.mkAfter (
        let
          # Interface configuration commands
          ifaceCommands = lib.concatMapStringsSep "\n" (link: ''
            echo "Configuring ${link.iface} → ${link.ip}/30 (peer: ${link.peerHost})"
            # Remove from bridge0 if present (no L2 bridging)
            if /sbin/ifconfig bridge0 2>/dev/null | grep -q "member: ${link.iface}"; then
              /sbin/ifconfig bridge0 deletem "${link.iface}" 2>/dev/null || true
              echo "  Removed ${link.iface} from bridge0"
            fi
            # Assign /30 IP
            /sbin/ifconfig "${link.iface}" inet "${link.ip}" netmask 255.255.255.252
            # Jumbo frames
            /sbin/ifconfig "${link.iface}" mtu 9000 2>/dev/null || true
          '') myLinks;

          # Static route commands for non-directly-connected subnets
          routeCommands = lib.concatMapStringsSep "\n" (
            route:
            if route != null then
              ''
                /sbin/route delete -net "${route.subnet}.0/30" 2>/dev/null || true
                /sbin/route add -net "${route.subnet}.0/30" "${route.gateway}"
                echo "Route: ${route.subnet}.0/30 via ${route.gateway}"
              ''
            else
              ""
          ) routesForHost;

          # /etc/hosts block: peers → their P2P IPs on the link to us
          # Plus our own .tb entry
          hostsBlock = lib.concatStringsSep "\n" (
            [ "${tbMyIP} ${cfg.exo.thunderboltHostname}.tb ${cfg.exo.thunderboltHostname}.thunderbolt" ]
            ++ tbHostsEntries
          );
          marker = "# --- TB cluster (managed by nix-darwin) ---";
        in
        ''
          echo "==> Thunderbolt L3 mesh: configuring point-to-point links..."

          # 1. Configure interfaces with /30 IPs
          ${ifaceCommands}

          # 2. Add static routes for indirect subnets
          ${routeCommands}

          # 3. Idempotent /etc/hosts management (replace existing block)
          # Scrub legacy 10.99.x entries written by older module versions
          # (those predate the marker). Match `IP HOSTNAME.tb` lines.
          /usr/bin/sed -i.scrubbak '/^10\.99\.[0-9]\{1,3\}\.[0-9]\{1,3\} [A-Za-z0-9-]\{1,\}\.tb /d' /etc/hosts
          if grep -q '${marker}' /etc/hosts 2>/dev/null; then
            # Remove old marked block and rewrite
            /usr/bin/sed -i.bak '/${marker}/,/${marker} end/d' /etc/hosts
          fi
          printf '\n${marker}\n${hostsBlock}\n${marker} end\n' >> /etc/hosts
          echo "Updated TB cluster entries in /etc/hosts"

          # 4. IP forwarding for relay hosts (those on >1 TB subnet).
          # Without this, traffic between non-adjacent hosts can't transit
          # through us. Sysctl is set immediately; the launchd daemon below
          # restores it on boot.
          ${lib.optionalString (builtins.length myLinks > 1) ''
            /usr/sbin/sysctl -w net.inet.ip.forwarding=1
            echo "IP forwarding enabled (relay node)"
          ''}

          echo "==> Thunderbolt L3 mesh configured."
        ''
      );

      # Boot-time IP forwarding restore for relay hosts. The activation
      # sysctl above only fires on `nh switch`; this LaunchDaemon runs at
      # boot to keep packet forwarding alive across reboots.
      launchd.daemons = lib.mkIf (builtins.length myLinks > 1) {
        tb-ip-forward = {
          serviceConfig = {
            Label = "dev.exo.tb-ip-forward";
            RunAtLoad = true;
            ProgramArguments = [
              "/usr/sbin/sysctl"
              "-w"
              "net.inet.ip.forwarding=1"
            ];
            StandardOutPath = "/tmp/tb-ip-forward.log";
            StandardErrorPath = "/tmp/tb-ip-forward.err";
          };
        };
      };
    })

    # exo: distributed inference cluster (Darwin launchd)
    (mkIf (isDarwin && cfg.exo.enable) {
      environment.systemPackages = [ cfg.exo.package ];

      environment.userLaunchAgents."org.exo-explore.exo.plist".text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>org.exo-explore.exo</string>
          <key>ProgramArguments</key>
          <array>
            <string>${exoLaunchScript}</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/tmp/exo.log</string>
          <key>StandardErrorPath</key>
          <string>/tmp/exo.err</string>
        </dict>
        </plist>
      '';
    })

    # Reverse SSH tunnel from the relay → LiteLLM host. autossh keeps it
    # up across AppGate flaps / desk-nxst-001 reboots; KeepAlive on the
    # launchd side restarts the wrapper if autossh itself ever dies.
    # Self-gated to the relay (myLinks > 1) so CK2/L75 are no-ops.
    (mkIf
      (isDarwin && cfg.exo.enable && cfg.exo.litellmTunnel.enable && tbEnabled && lib.length myLinks > 1)
      {
        environment.systemPackages = [ pkgs.autossh ];

        launchd.daemons.exo-litellm-tunnel = {
          serviceConfig = {
            Label = "dev.exo.litellm-tunnel";
            RunAtLoad = true;
            KeepAlive = true;
            EnvironmentVariables = {
              # autossh's "first connection must succeed within N seconds"
              # gate would mark the tunnel dead during AppGate bring-up.
              # 0 disables the gate; we rely on ServerAlive* instead.
              AUTOSSH_GATETIME = "0";
            };
            ProgramArguments = [
              "${pkgs.autossh}/bin/autossh"
              "-M"
              "0" # no monitoring port; ServerAliveInterval handles liveness
              "-N" # no remote command
              "-T" # no TTY
              "-o"
              "ExitOnForwardFailure=yes"
              "-o"
              "ServerAliveInterval=30"
              "-o"
              "ServerAliveCountMax=3"
              "-o"
              "StrictHostKeyChecking=accept-new"
              "-o"
              "BatchMode=yes"
              "-o"
              "UserKnownHostsFile=/var/root/.ssh/known_hosts.exo-tunnel"
              "-i"
              (toString cfg.exo.litellmTunnel.identityFile)
              "-R"
              "127.0.0.1:${toString cfg.exo.apiPort}:127.0.0.1:${toString cfg.exo.apiPort}"
              "${cfg.exo.litellmTunnel.remoteUser}@${cfg.exo.litellmTunnel.remoteHost}"
            ];
            StandardOutPath = "/tmp/exo-litellm-tunnel.log";
            StandardErrorPath = "/tmp/exo-litellm-tunnel.err";
          };
        };
      }
    )

    # exo: distributed inference cluster (Linux systemd)
    (optionalAttrs isLinux (
      mkIf cfg.exo.enable {
        environment.systemPackages = [ cfg.exo.package ];

        systemd.user.services.exo = {
          description = "exo distributed inference cluster";
          wantedBy = [ "default.target" ];
          after = [ "network.target" ];
          path = [ cfg.exo.package ];
          script = ''
            ${optionalString (cfg.exo.listenInterfaces != [ ]) ''
              _exo_listen_addrs=""
              ${exoListenAddrsScript}
              [ -n "$_exo_listen_addrs" ] && export EXO_LISTEN_ADDRS="$_exo_listen_addrs"
              unset _exo_addr
            ''}
            exec ${cfg.exo.package}/bin/exo \
              --api-port ${toString cfg.exo.apiPort} \
              --libp2p-port ${toString cfg.exo.libp2pPort} \
              ${optionalString (cfg.exo.peers != [ ]) "--bootstrap-peers ${concatStringsSep "," cfg.exo.peers}"}
          '';
          environment = {
            EXO_BOOTSTRAP_PEERS = concatStringsSep "," cfg.exo.peers;
          };
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      }
    ))

    # Claw3D: 3D virtual office for Hermes agents
    (mkIf cfg.claw3d.enable {
      environment.systemPackages = [ cfg.claw3d.package ];

      home-manager.users.${user.name}.home = {
        file.".hermes/claw3d.env".text = ''
          NEXT_PUBLIC_GATEWAY_URL=ws://localhost:${toString cfg.claw3d.adapterPort}
          HERMES_API_URL=${cfg.claw3d.hermesApiUrl}
          HERMES_ADAPTER_PORT=${toString cfg.claw3d.adapterPort}
          HERMES_API_KEY=${cfg.claw3d.gatewayToken}
          HERMES_MODEL=hermes-agent
          HERMES_AGENT_NAME=Hermes
          PORT=${toString cfg.claw3d.port}
          HOST=127.0.0.1
          CLAW3D_GATEWAY_ADAPTER_TYPE=hermes
        '';

      };

      # Studio settings: written as a mutable file (not a symlink)
      # so the Claw3D server can persist runtime changes.
      system.activationScripts.postActivation.text =
        let
          settingsJson = builtins.toJSON {
            version = 1;
            gateway = {
              url = "ws://localhost:${toString cfg.claw3d.adapterPort}";
              token = cfg.claw3d.gatewayToken;
              adapterType = "hermes";
              profiles = {
                hermes = {
                  url = "ws://localhost:${toString cfg.claw3d.adapterPort}";
                  token = cfg.claw3d.gatewayToken;
                };
              };
            };
          };
          settingsFile = pkgs.writeText "claw3d-settings.json" settingsJson;
          userHome = "/Users/${user.name}";
        in
        ''
          # Claw3D: seed studio settings as a mutable file
          settings_dir="${userHome}/.openclaw/claw3d"
          settings_file="$settings_dir/settings.json"
          mkdir -p "$settings_dir"
          [ -L "$settings_file" ] && rm -f "$settings_file"
          cp "${settingsFile}" "$settings_file"
          chmod 644 "$settings_file"
          chown ${user.name} "$settings_dir" "$settings_file"
        '';
    })

    # Claw3D launchd agents (Darwin)
    (optionalAttrs isDarwin (
      mkIf cfg.claw3d.enable ({
        launchd.user.agents.claw3d-hermes-adapter = {
          command = "${cfg.claw3d.package}/bin/claw3d-hermes-adapter";
          serviceConfig = {
            Label = "com.claw3d.hermes-adapter";
            RunAtLoad = true;
            KeepAlive = true;
            EnvironmentVariables = {
              HERMES_API_URL = cfg.claw3d.hermesApiUrl;
              HERMES_ADAPTER_PORT = toString cfg.claw3d.adapterPort;
              HERMES_API_KEY = cfg.claw3d.gatewayToken;
              HERMES_MODEL = "hermes-agent";
              HERMES_AGENT_NAME = "Hermes";
            };
            StandardOutPath = "/tmp/claw3d-adapter.log";
            StandardErrorPath = "/tmp/claw3d-adapter.err";
          };
        };

        launchd.user.agents.claw3d = {
          command = "${cfg.claw3d.package}/bin/claw3d";
          serviceConfig = {
            Label = "com.claw3d.studio";
            RunAtLoad = true;
            KeepAlive = true;
            EnvironmentVariables = {
              PORT = toString cfg.claw3d.port;
              HOST = "127.0.0.1";
              NODE_ENV = "production";
              NEXT_PUBLIC_GATEWAY_URL = "ws://localhost:${toString cfg.claw3d.adapterPort}";
              CLAW3D_GATEWAY_ADAPTER_TYPE = "hermes";
              UPSTREAM_ALLOWLIST = "localhost";
            };
            StandardOutPath = "/tmp/claw3d.log";
            StandardErrorPath = "/tmp/claw3d.err";
          };
        };
      })
    ))

    # Claw3D systemd services (Linux)
    (optionalAttrs isLinux (
      mkIf cfg.claw3d.enable {
        systemd.user.services.claw3d-hermes-adapter = {
          description = "Claw3D Hermes Gateway Adapter";
          wantedBy = [ "default.target" ];
          after = [ "network.target" ];
          environment = {
            HERMES_API_URL = cfg.claw3d.hermesApiUrl;
            HERMES_ADAPTER_PORT = toString cfg.claw3d.adapterPort;
            HERMES_API_KEY = cfg.claw3d.gatewayToken;
            HERMES_MODEL = "hermes-agent";
            HERMES_AGENT_NAME = "Hermes";
          };
          serviceConfig = {
            ExecStart = "${cfg.claw3d.package}/bin/claw3d-hermes-adapter";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        systemd.user.services.claw3d = {
          description = "Claw3D 3D Virtual Office";
          wantedBy = [ "default.target" ];
          after = [
            "network.target"
            "claw3d-hermes-adapter.service"
          ];
          environment = {
            PORT = toString cfg.claw3d.port;
            HOST = "127.0.0.1";
            NODE_ENV = "production";
            NEXT_PUBLIC_GATEWAY_URL = "ws://localhost:${toString cfg.claw3d.adapterPort}";
            CLAW3D_GATEWAY_ADAPTER_TYPE = "hermes";
            UPSTREAM_ALLOWLIST = "localhost";
          };
          serviceConfig = {
            ExecStart = "${cfg.claw3d.package}/bin/claw3d";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      }
    ))
  ]);
}
