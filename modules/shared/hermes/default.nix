{
  config,
  lib,
  pkgs,
  user,
  hermes,
  hippo,
  system,
  ...
}:

with lib;

let
  cfg = config.local.hermes;
  ollamaBaseUrl = "${cfg.ollamaHost}:${toString cfg.ollamaPort}/v1";
  exoBaseUrl = "http://localhost:${toString cfg.exo.apiPort}/v1";
  # The effective local base_url: exo takes priority over ollama when both are configured
  localBaseUrl = if cfg.exo.enable then exoBaseUrl else ollamaBaseUrl;
  # Helper: resolve interface names to libp2p listen multiaddrs at runtime
  exoListenAddrsScript = concatMapStringsSep "\n" (iface: ''
    _exo_addr=$(ipconfig getifaddr ${iface} 2>/dev/null || ip -4 addr show ${iface} 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -n "$_exo_addr" ] && _exo_listen_addrs="$_exo_listen_addrs /ip4/$_exo_addr/tcp/${toString cfg.exo.libp2pPort}"
  '') cfg.exo.listenInterfaces;
  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];

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
      onnxruntimeOverlay = final: prev: {
        onnxruntime = prev.onnxruntime.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/60/69/6c40720201012c6af9aa7d4ecdd620e521bd806dc6269d636fdd5c5aeebe/onnxruntime-1.24.4-cp311-cp311-macosx_14_0_arm64.whl";
            hash = "sha256-C9/Ojppkl87FhKq0B7cb9pfaxeG3t5dK3FC/dTO9s6I=";
          };
        });
      };
      cffiOverlay = final: prev: {
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

  # Pre-fetched ONNX Runtime for hippo (ort-sys 2.0.0-rc.10 expects 1.22.0)
  # pkgs.onnxruntime is broken on nixpkgs-unstable (removed darwin.apple_sdk_11_0)
  onnxruntimeVersion = "1.22.0";
  onnxruntimePrebuilt =
    let
      srcs = {
        "aarch64-darwin" = pkgs.fetchzip {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v${onnxruntimeVersion}/onnxruntime-osx-arm64-${onnxruntimeVersion}.tgz";
          hash = "sha256-RQITtO4v6S5nB5B+sOkQignjHM/l7ja+hVDLvKQ1oAw=";
        };
        "x86_64-linux" = pkgs.fetchzip {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v${onnxruntimeVersion}/onnxruntime-linux-x64-${onnxruntimeVersion}.tgz";
          hash = lib.fakeHash;
        };
      };
    in
    srcs.${system} or (throw "unsupported system for onnxruntime: ${system}");
  onnxruntimeDylibName = if isDarwin then "libonnxruntime.dylib" else "libonnxruntime.so";

  # Hippo: AI-generated insights memory system (MCP server)
  hippoPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "hippo-server";
    version = "0.1.0";
    src = hippo;

    cargoLock.lockFile = "${hippo}/Cargo.lock";

    # Only build the hippo crate (produces hippo-server binary)
    cargoBuildFlags = [
      "-p"
      "hippo"
    ];

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    # Frameworks (Security, SystemConfiguration, CoreFoundation) are provided
    # by apple-sdk through stdenv automatically on modern nixpkgs.

    # Point ort-sys to pre-fetched ONNX Runtime (prevents download in Nix sandbox)
    env.ORT_LIB_LOCATION = "${onnxruntimePrebuilt}/lib";

    # Tests require the fastembed model (downloaded lazily) — skip in sandbox
    doCheck = false;

    postInstall = ''
      wrapProgram $out/bin/hippo-server \
        --set ORT_DYLIB_PATH "${onnxruntimePrebuilt}/lib/${onnxruntimeDylibName}" \
        --prefix DYLD_LIBRARY_PATH : "${onnxruntimePrebuilt}/lib"
    '';

    meta = with lib; {
      description = "AI-generated insights memory system via MCP";
      homepage = "https://github.com/symposium-dev/hippo";
      license = with licenses; [
        mit
        asl20
      ];
      mainProgram = "hippo-server";
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
        default = "https://vertex-proxy.sdgr.app";
        description = "Vertex AI proxy base URL (Anthropic SDK appends /v1/messages)";
      };

      model = mkOption {
        type = types.str;
        default = "claude-opus-4-6";
        description = "Model to use via Vertex proxy";
      };
    };

    delegation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route subtasks to local LLM";
      };
    };

    auxiliary = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route vision/web/compression to local LLM";
      };
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

    hippo = {
      enable = mkEnableOption "Hippo AI-generated insights memory system (MCP server for Hermes)";

      package = mkOption {
        type = types.package;
        default = hippoPackage;
        description = "The hippo-server package";
      };

      memoryDir = mkOption {
        type = types.str;
        default = "~/.hippo";
        description = "Directory for storing hippo memory/insight files";
      };

      logLevel = mkOption {
        type = types.enum [
          "error"
          "warning"
          "info"
          "debug"
        ];
        default = "info";
        description = "Hippo server log level";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Common config: package, config file, shell init
    {
      environment.systemPackages = [ cfg.package ] ++ optional cfg.hippo.enable cfg.hippo.package;

      home-manager.users.${user.name}.home.file.".hermes/config.yaml".text = concatStringsSep "\n" (
        [
          "# Main model: Vertex AI proxy (Claude) — heavy lifting"
          "model:"
          "  default: \"${cfg.vertexProxy.model}\""
          "  provider: \"anthropic\""
          "  base_url: \"${cfg.vertexProxy.baseURL}\""
          ""
        ]
        ++ optionals cfg.delegation.enable [
          "# Delegate small tasks / tool calls to local LLM"
          "delegation:"
          "  base_url: \"${localBaseUrl}\""
          "  model: \"${cfg.localModel}\""
          "  api_key: \"ollama\""
          ""
        ]
        ++ optionals cfg.auxiliary.enable [
          "# Auxiliary models use local LLM"
          "auxiliary:"
          "  vision:"
          "    base_url: \"${localBaseUrl}\""
          "    model: \"${cfg.localModel}\""
          "    api_key: \"ollama\""
          "  web_extract:"
          "    base_url: \"${localBaseUrl}\""
          "    model: \"${cfg.localModel}\""
          "    api_key: \"ollama\""
          "  compression:"
          "    base_url: \"${localBaseUrl}\""
          "    model: \"${cfg.localModel}\""
          "    api_key: \"ollama\""
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
        ++ optionals cfg.hippo.enable [
          "# MCP Servers"
          "mcp_servers:"
          "  hippo:"
          "    command: \"${cfg.hippo.package}/bin/hippo-server\""
          "    args:"
          "      - \"--memory-dir\""
          "      - \"${cfg.hippo.memoryDir}\""
          "    env:"
          "      HIPPO_LOG: \"${cfg.hippo.logLevel}\""
          ""
        ]
        ++ [
          "agent:"
          "  tool_use_enforcement: \"auto\""
          ""
          "terminal:"
          "  backend: local"
          "  persistent_shell: true"
          ""
          "memory:"
          "  memory_enabled: true"
        ]
      );

      programs.zsh.shellInit = mkAfter ''
        # Hermes Agent: Vertex proxy env vars and auth
        export ANTHROPIC_VERTEX_PROJECT_ID="vertex-code-454718"
        export CLOUD_ML_REGION="us-east5"

        # faster-whisper model is already cached locally; suppress the
        # huggingface_hub unauthenticated-request warning at transcription time.
        export HF_HUB_OFFLINE=1

        if command -v gcloud >/dev/null 2>&1; then
          _hermes_token="$(gcloud auth print-identity-token 2>/dev/null || echo "")"
          if [ -n "$_hermes_token" ]; then
            mkdir -p "$HOME/.hermes"
            echo "ANTHROPIC_API_KEY=$_hermes_token" > "$HOME/.hermes/.env"
          fi
          unset _hermes_token
        fi
      '';
    }

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
            <string>${cfg.exo.package}/bin/exo</string>
            <string>--api-port</string>
            <string>${toString cfg.exo.apiPort}</string>
            <string>--libp2p-port</string>
            <string>${toString cfg.exo.libp2pPort}</string>
            ${optionalString (cfg.exo.peers != [ ]) ''
              <string>--bootstrap-peers</string>
              <string>${concatStringsSep "," cfg.exo.peers}</string>
            ''}
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/tmp/exo.log</string>
          <key>StandardErrorPath</key>
          <string>/tmp/exo.err</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>EXO_BOOTSTRAP_PEERS</key>
            <string>${concatStringsSep "," cfg.exo.peers}</string>
            ${optionalString (cfg.exo.listenInterfaces != [ ]) ''
              <key>EXO_LISTEN_INTERFACES</key>
              <string>${concatStringsSep "," cfg.exo.listenInterfaces}</string>
            ''}
          </dict>
        </dict>
        </plist>
      '';
    })

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
