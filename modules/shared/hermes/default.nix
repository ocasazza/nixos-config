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

  # Generate config text from template
  configText = import ./config-template.nix {
    inherit
      lib
      cfg
      user
      ;
  };

  # Build a list of secret substitutions for the activation script.
  # Each entry is a bash snippet that replaces a placeholder in the
  # generated config with the real secret value.
  #
  # Supported placeholders:
  #   $LITELLM_HERMES_API_KEY  → read from cfg.litellm.virtualKeyFile
  #   $AZURE_API_KEY            → read from cfg.delegation.azureKeyFile
  #   $GEMINI_API_KEY           → read from cfg.mainModel.geminiKeyFile
  #   $VERTEX_PROXY_ID_TOKEN    → read from gcloud auth print-identity-token
  #
  # Add more as needed following the same pattern.
  secretSubstitutions =
    let
      # Use sed without -i (BSD/GNU portable) and redirect to a temp file.
      # The \$ escapes the $ in the double-quoted Nix string so bash
      # does NOT expand the placeholder — sed sees it literally.
      # The target file is passed as $TMPFILE from the activation script.
      mkSed = placeholder: filePath: ''
        if [ -r "${toString filePath}" ]; then
          VALUE="$(cut -d= -f2- < "${toString filePath}")"
          run sed "s|\${placeholder}|$VALUE|g" "$TMPFILE" > "$TMPFILE.sed"
          run mv -f "$TMPFILE.sed" "$TMPFILE"
        fi
      '';
    in
    concatStringsSep "\n" (
      (optional (cfg.litellm.enable && cfg.litellm.virtualKeyFile != null) (
        mkSed "$LITELLM_HERMES_API_KEY" cfg.litellm.virtualKeyFile
      ))
      ++ (optional (cfg.delegation.azureKeyFile != null) (
        mkSed "$AZURE_API_KEY" cfg.delegation.azureKeyFile
      ))
      ++ (optional (cfg.mainModel.geminiKeyFile != null) (
        mkSed "$GEMINI_API_KEY" cfg.mainModel.geminiKeyFile
      ))
      ++ (optional cfg.mainModel.vertexProxyIdToken ''
        TOKEN="$(${pkgs.google-cloud-sdk}/bin/gcloud auth print-identity-token 2>/dev/null || true)"
        if [ -n "$TOKEN" ]; then
          run sed "s|\$VERTEX_PROXY_ID_TOKEN|$TOKEN|g" "$TMPFILE" > "$TMPFILE.sed"
          run mv -f "$TMPFILE.sed" "$TMPFILE"
        fi
      '')
    );
in
{
  imports = [
    (import ./options.nix {
      inherit lib;
      defaultPackage = package;
    })
  ];

  config = mkIf cfg.enable (mkMerge [
    # Common config: package, config file, shell init
    {
      environment.systemPackages = [ cfg.package ];

      # `force = true`: at activation, the home.activation.hermesConfigInjectSecrets
      # script (defined below) replaces this symlink with a real, key-injected
      # file. On the next activation HM would normally try to back up the
      # real file to `.bak` before placing a fresh symlink — and barf if the
      # `.bak` from the prior activation is still around. Force-overwrite
      # skips both the backup and the collision.
      home-manager.users.${user.name}.home.file.".hermes/config.yaml" = {
        force = true;
        text = configText;
      };

      programs.zsh.shellInit = mkAfter (''
        # faster-whisper model is already cached locally; suppress the
        # huggingface_hub unauthenticated-request warning at transcription time.
        export HF_HUB_OFFLINE=1
      '');
    }

    # One-shot at activation: render ~/.hermes/config.yaml from the
    # nix-store template with all sops-decrypted secrets spliced in.
    # Replaces the previous per-shell sed approach, which had three
    # problems: (1) BSD-vs-GNU sed-i incompatibility on macOS, (2) raced
    # when hermes was launched outside an interactive shell (launchd,
    # cron), (3) ran on every shell open for a one-shot op.
    #
    # Lives in its own mkMerge block so it doesn't collide with the
    # `home-manager.users.<u>.home.file."/.hermes/config.yaml".text`
    # attribute defined above (Nix attribute paths can't repeat at
    # the same nesting level within a single attrset literal).
    (mkIf (secretSubstitutions != "") {
      home-manager.users.${user.name} =
        { lib, ... }:
        {
          home.activation.hermesConfigInjectSecrets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            if [ -L "$HOME/.hermes/config.yaml" ]; then
              TEMPLATE="$(readlink "$HOME/.hermes/config.yaml")"
              # Use mktemp so a previous failed run can't leave a stale
              # .new file with restrictive permissions behind.
              TMPFILE="$(mktemp "$HOME/.hermes/.config.yaml.XXXXXXXXXX")"
              run cp "$TEMPLATE" "$TMPFILE"
              ${secretSubstitutions}
              run mv -f "$TMPFILE" "$HOME/.hermes/config.yaml"
              run chmod 0400 "$HOME/.hermes/config.yaml"
            fi
          '';
        };
    })

    # ~/.hermes/.env: hermes loads this with override=True, so empty
    # values (e.g. GOOGLE_API_KEY=) wipe shell env vars that our
    # zsh.shellInit sets. Write a clean .env at activation so stale
    # entries from `hermes setup` don't break provider auth.
    {
      home-manager.users.${user.name} =
        { lib, ... }:
        {
          home.activation.hermesEnvCleanup = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            run install -m 0600 /dev/null "$HOME/.hermes/.env"
            echo "# Managed by nix-darwin hermes module — do not edit." \
              > "$HOME/.hermes/.env"
          '';
        };
    }

    # SOUL.md: global agent identity (only written when soulMd option is set)
    (mkIf (cfg.soulMd != "") {
      home-manager.users.${user.name}.home.file.".hermes/SOUL.md".text = cfg.soulMd;
    })

    # Custom display skins managed by hermes-mod (not Nix).
    # Reference copy: modules/shared/hermes/skins/<name>.yaml
    # Live file: ~/.hermes/skins/<name>.yaml (writable, managed by hermes-mod)

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

    # Darwin (macOS): portaudio for CLI voice mode microphone input
    (optionalAttrs isDarwin (
      mkIf cfg.voice.enable {
        homebrew.brews = [ "portaudio" ];
      }
    ))
  ]);
}
