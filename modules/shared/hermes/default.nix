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

  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];

  # Import package logic
  package = import ./package.nix {
    inherit
      pkgs
      lib
      hermes
      system
      cfg
      ;
  };

in
{
  imports = [
    (import ./options.nix {
      inherit lib;
      defaultPackage = package;
    })
  ];

  config = mkIf cfg.enable (mkMerge [
    # Common config: package, shell init
    {
      environment.systemPackages = [ cfg.package ];

      programs.zsh.shellInit = mkAfter (''
        # faster-whisper model is already cached locally; suppress the
        # huggingface_hub unauthenticated-request warning at transcription time.
        export HF_HUB_OFFLINE=1
      '');
    }

    # Declarative config.yaml via SOPS templates in Home Manager
    {
      home-manager.users.${user.name} = hmConfig: {
        sops = {
          # Use the same key file as system level
          age.keyFile = lib.mkDefault "${hmConfig.config.home.homeDirectory}/.config/sops/age/keys.txt";

          secrets = {
            # Use a hermes-scoped name to avoid shadowing the system-level
            # sops secret of the same name (opencode module also declares
            # litellm-key-opencode-darwin at system scope).
            "hermes-litellm-key" = {
              sopsFile = ../../../secrets/litellm-key-hybrid-olive.yaml;
              key = "litellm_api_key";
            };
            "azure-api-key-opencode-darwin" = {
              sopsFile = ../../../secrets/azure-api-key-opencode-darwin.yaml;
              key = "azure_api_key";
            };
            # gemini-enterprise-api-key is intentionally omitted until the
            # yaml is encrypted (REPLACE_WITH_ACTUAL_KEY placeholder now).
          };

          templates."hermes-config.yaml" = {
            path = "${hmConfig.config.home.homeDirectory}/.hermes/config.yaml";
            content = builtins.toJSON (
              import ./config-set.nix {
                inherit lib cfg;
                config = hmConfig.config;
              }
            );
          };
        };

        # ~/.hermes/.env cleanup
        home.activation.hermesEnvCleanup = hmConfig.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run install -m 0600 /dev/null "$HOME/.hermes/.env"
          echo "# Managed by nix-darwin hermes module — do not edit." \
            > "$HOME/.hermes/.env"
        '';
      };
    }

    # SOUL.md: global agent identity
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

    # Voice mode dependencies
    (optionalAttrs isLinux (mkIf cfg.voice.enable { environment.systemPackages = [ pkgs.portaudio ]; }))
    (optionalAttrs isDarwin (mkIf cfg.voice.enable { homebrew.brews = [ "portaudio" ]; }))
  ]);
}
