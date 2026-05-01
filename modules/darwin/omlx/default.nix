# omlx — LLM inference server with continuous batching & tiered KV cache.
#
# Exposes an OpenAI-compatible API at localhost:8000/v1 and optionally
# provides local STT/TTS via mlx-audio (when installed with [audio]).
# Managed by a launchd user agent so it starts on login and auto-restarts
# on crash.
#
# Model storage defaults to ~/.omlx/models (same as upstream). Point your
# opencode provider at http://localhost:8000/v1 to use omlx as a local
# inference backend with MLX caching benefits.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.omlx;
  user = config.local.user.name or "casazza";

  # We use the upstream-preferred default model dir, but allow override.
  modelDir = cfg.modelDir;
  port = cfg.port;
in
{
  options.local.omlx = {
    enable = lib.mkEnableOption "oMLX local LLM inference server";

    modelDir = lib.mkOption {
      type = lib.types.str;
      default = "/Users/${user}/.omlx/models";
      description = "Directory where omlx discovers MLX-format models.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port for the omlx OpenAI-compatible HTTP API.";
    };

    maxModelMemory = lib.mkOption {
      type = lib.types.str;
      default = "32GB";
      description = "Memory limit for loaded models.";
    };

    hotCacheMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "20%";
      description = "In-memory hot cache size as percentage of system RAM.";
    };

    ssdCacheDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/Users/${user}/.omlx/cache";
      description = "Directory for the cold-tier SSD KV cache. Disabled if null.";
    };

    maxConcurrentRequests = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Maximum concurrent inference requests.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure the model directory exists.
    system.activationScripts.preActivation.text = lib.mkAfter ''
      mkdir -p ${modelDir}
      ${lib.optionalString (cfg.ssdCacheDir != null) "mkdir -p ${cfg.ssdCacheDir}"}
    '';

    # launchd user agent: starts omlx serve on login, restarts on crash.
    launchd.user.agents.omlx-server = {
      serviceConfig = {
        Label = "ai.omlx.server";
        ProgramArguments = [
          "${pkgs.omlx}/bin/omlx"
          "serve"
          "--model-dir"
          modelDir
          "--port"
          (toString port)
          "--max-model-memory"
          cfg.maxModelMemory
          "--hot-cache-max-size"
          cfg.hotCacheMaxSize
          "--max-concurrent-requests"
          (toString cfg.maxConcurrentRequests)
        ]
        ++ lib.optionals (cfg.ssdCacheDir != null) [
          "--paged-ssd-cache-dir"
          cfg.ssdCacheDir
        ];
        KeepAlive = {
          Crashed = true;
          SuccessfulExit = false;
        };
        RunAtLoad = true;
        StandardOutPath = "/Users/${user}/.omlx/logs/launchd.log";
        StandardErrorPath = "/Users/${user}/.omlx/logs/launchd.err";
        EnvironmentVariables = {
          # Ensure Python can find the venv even under launchd's minimal env.
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin";
        };
      };
    };

    # Expose omlx provider config through home-manager so modules/darwin/opencode
    # can reference it easily. We put it here so the omlx module owns its own
    # endpoint configuration.
    home-manager.users.${user}.home.sessionVariables = {
      OMLX_API_URL = "http://localhost:${toString port}/v1";
    };
  };
}
