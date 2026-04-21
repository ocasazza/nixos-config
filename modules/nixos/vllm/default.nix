# vLLM as a systemd service.
#
# vLLM in nixpkgs is a python package (no top-level binary), so we wrap
# `python -m vllm.entrypoints.openai.api_server` in a long-running unit.
#
# Why vLLM (vs. ollama):
#   - Continuous batching and PagedAttention give 5-20× higher throughput
#     on a single GPU than llama.cpp-based servers.
#   - Native OpenAI-compatible API (no proxy needed).
#   - First-class tensor parallelism if you ever add a second GPU.
#
# Why one service per model (vs. swapping):
#   - vLLM holds the entire model in VRAM and aggressively pre-allocates
#     the KV cache. Hot-swapping would require restarting the process,
#     defeating the point of always-warm inference.
#   - On a single 24GB card you generally fit ONE big model + ONE small
#     model concurrently if you cap each one's `gpuMemoryUtilization`.
#     For two models, run two service instances on different ports.
#
# Resource sharing on a 24GB RTX 3090 Ti:
#   - vLLM's `--gpu-memory-utilization` is the FRACTION of total VRAM
#     it will claim *for itself*. With two services on the same GPU,
#     set them to 0.55 and 0.30 (etc.) so the sum stays < 0.90 and
#     leaves headroom for the driver and any compositor.
#
# Usage:
#   local.vllm = {
#     enable = true;
#     services = {
#       coder = {
#         model = "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ";
#         port = 8000;
#         gpuMemoryUtilization = 0.55;
#         maxModelLen = 16384;
#         extraArgs = [ "--quantization" "awq_marlin" ];
#       };
#       chat = {
#         model = "meta-llama/Llama-3.2-3B-Instruct";
#         port = 8001;
#         gpuMemoryUtilization = 0.20;
#         maxModelLen = 8192;
#       };
#     };
#   };
#
# Verify:
#   curl http://luna:8000/v1/models
#   curl http://luna:8000/v1/chat/completions \
#     -H 'Content-Type: application/json' \
#     -d '{"model":"Qwen/Qwen2.5-Coder-32B-Instruct-AWQ","messages":[{"role":"user","content":"ping"}]}'
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.vllm;

  serviceOpts =
    { name, ... }:
    {
      options = {
        model = mkOption {
          type = types.str;
          example = "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ";
          description = ''
            Hugging Face model id (or local path) that vLLM will load.
            The model is fetched into `cfg.cacheDir` on first start; expect
            a 5-30 minute initial download depending on size.
          '';
        };

        port = mkOption {
          type = types.port;
          description = "TCP port for the OpenAI-compatible API.";
        };

        host = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Bind address. Defaults to all interfaces so the LAN can reach
            it. Use `127.0.0.1` if you only want loopback access and put
            a reverse proxy in front for auth.
          '';
        };

        gpuMemoryUtilization = mkOption {
          type = types.float;
          default = 0.90;
          description = ''
            Fraction of total GPU memory vLLM is allowed to claim for
            weights + KV cache. With multiple services on one GPU the
            sum across services should stay <= 0.90.
          '';
        };

        maxModelLen = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Hard cap on context length. Setting this lower than the
            model's native max can dramatically reduce KV cache memory
            (which scales linearly with context length).
          '';
        };

        tensorParallelSize = mkOption {
          type = types.int;
          default = 1;
          description = ''
            Number of GPUs to shard the model across. luna currently has
            one 3090 Ti, so leave this at 1.
          '';
        };

        dtype = mkOption {
          type = types.enum [
            "auto"
            "half"
            "float16"
            "bfloat16"
            "float"
            "float32"
          ];
          default = "auto";
          description = "Data type for model weights and activations.";
        };

        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "--quantization"
            "awq_marlin"
          ];
          description = "Extra CLI flags appended to the vllm serve invocation.";
        };

        environment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Extra environment variables for this service instance.";
        };
      };
    };

  # Build the vllm CLI invocation for one service.
  # Used inside a shell script so we can inject HUGGING_FACE_HUB_TOKEN
  # without it ever appearing in the systemd unit text.
  # vllm CLI args (everything except the python interpreter prefix).
  vllmArgs =
    svc:
    lib.escapeShellArgs (
      [
        "-m"
        "vllm.entrypoints.openai.api_server"
        "--model"
        svc.model
        "--host"
        svc.host
        "--port"
        (toString svc.port)
        "--gpu-memory-utilization"
        (toString svc.gpuMemoryUtilization)
        "--tensor-parallel-size"
        (toString svc.tensorParallelSize)
        "--dtype"
        svc.dtype
        "--download-dir"
        "${cfg.cacheDir}/huggingface"
      ]
      ++ lib.optionals (svc.maxModelLen != null) [
        "--max-model-len"
        (toString svc.maxModelLen)
      ]
      ++ svc.extraArgs
    );

  # Wrapper script: bootstraps a uv-managed venv at first start (cached
  # under cfg.venvDir), then `exec`s vllm into it. nixpkgs's `vllm`
  # is unbuildable on x86_64-linux at the time of writing (cmake
  # incompatibility against the bundled torch), so we sidestep it with
  # the upstream pip wheels — same source, fewer breakage points.
  #
  # Version-tracked venv: we stamp `cfg.venvDir/.vllm-version` with the
  # currently-installed version. When `cfg.vllmVersion` changes (e.g.
  # 0.6.4.post1 → 0.10.0), the script wipes and recreates the venv
  # before pip-installing, instead of trying to upgrade in place
  # (uv pip install --upgrade often hits torch ABI conflicts during
  # major vllm version bumps).
  startScript =
    name: svc:
    pkgs.writeShellScript "vllm-${name}-start" ''
      set -eu

      VENV="${cfg.venvDir}"
      VLLM_VERSION="${cfg.vllmVersion}"
      VERSION_STAMP="$VENV/.vllm-version"

      # Recreate venv if the requested vllm version differs from what's
      # stamped (or stamp file missing → fresh bootstrap).
      if [ -x "$VENV/bin/python" ] && [ -f "$VERSION_STAMP" ]; then
        installed_version="$(cat "$VERSION_STAMP")"
        if [ "$installed_version" != "$VLLM_VERSION" ]; then
          echo "vllm: version changed ($installed_version → $VLLM_VERSION), recreating venv"
          rm -rf "$VENV"
        fi
      fi

      if [ ! -x "$VENV/bin/python" ]; then
        echo "vllm: bootstrapping venv at $VENV"
        ${cfg.uv}/bin/uv venv --python ${cfg.python}/bin/python "$VENV"
      fi

      # Pin vllm. uv's `pip install` is idempotent — when the
      # exact version is already installed it's a near-instant no-op,
      # so we always run it on service start to pick up version bumps.
      #
      # `setuptools` is needed by triton's runtime kernel JIT (it
      # imports `setuptools` lazily when compiling CUDA backends), and
      # vllm doesn't pull it in transitively.
      ${cfg.uv}/bin/uv pip install --python "$VENV/bin/python" \
        --quiet \
        "vllm==$VLLM_VERSION" \
        "setuptools"

      # Stamp the venv with the version we just installed so future
      # restarts can detect drift.
      echo "$VLLM_VERSION" > "$VERSION_STAMP"

      # Patchelf triton's bundled `ptxas` (and `ptxas-blackwell`) so they
      # use a real glibc loader instead of `/lib64/ld-linux-x86-64.so.2`,
      # which doesn't exist on NixOS without `programs.nix-ld`. Without
      # this, the first kernel JIT call from torch.compile dies with:
      #   CalledProcessError: Command '[…/ptxas, --version]' exit 127
      #   "Could not start dynamically linked executable … stub-ld"
      # Idempotent: patchelf rewrites the interpreter in place each run,
      # so re-running on already-patched binaries is a no-op. We rerun
      # unconditionally so a venv recreate (vllm version bump) reapplies.
      TRITON_BIN="$VENV/lib/python${cfg.python.pythonVersion}/site-packages/triton/backends/nvidia/bin"
      if [ -d "$TRITON_BIN" ]; then
        GLIBC_INTERP="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
        for ptx in "$TRITON_BIN/ptxas" "$TRITON_BIN/ptxas-blackwell"; do
          if [ -x "$ptx" ]; then
            ${pkgs.patchelf}/bin/patchelf --set-interpreter "$GLIBC_INTERP" "$ptx" || true
          fi
        done
      fi

      ${lib.optionalString (cfg.huggingfaceTokenFile != null) ''
        if [ -r "${cfg.huggingfaceTokenFile}" ]; then
          export HUGGING_FACE_HUB_TOKEN="$(cat "${cfg.huggingfaceTokenFile}")"
        fi
      ''}

      exec "$VENV/bin/python" ${vllmArgs svc}
    '';
in

{
  options.local.vllm = {
    enable = mkEnableOption "vLLM OpenAI-compatible inference servers";

    # vllm in nixpkgs is currently broken to build from source on
    # x86_64-linux (cmake incompatibility with the bundled torch).
    # We install vllm into a uv-managed venv at first service start
    # using upstream PyPI wheels, which already ship CUDA bundled.
    vllmVersion = mkOption {
      type = types.str;
      default = "0.10.0";
      description = ''
        vllm version to pip-install into the venv. Pin to a known-good
        release. PyPI: https://pypi.org/project/vllm/#history

        Major-version notes:
          * 0.10.0 — adds Qwen3 + Qwen3-Coder (MoE) support, native
                     FP8 quantization, improved tensor parallelism for
                     mixed-VRAM multi-GPU setups (3090 Ti + RTX 4000).
          * 0.6.x  — last release before Qwen3 architecture; tied to
                     transformers <4.55. Used historically.

        Changing this triggers a venv recreation on next service
        start (the wrapper stamps `.vllm-version` and recreates when
        it differs).
      '';
    };

    python = mkOption {
      type = types.package;
      default = pkgs.python311;
      defaultText = literalExpression "pkgs.python311";
      description = ''
        Python interpreter the venv is built around. vllm wheels
        currently target Python 3.10 / 3.11 / 3.12; 3.13 is unsupported.
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
      default = "/var/lib/vllm/venv";
      description = ''
        Persistent venv location. Survives nixos-rebuilds. Wipe it if
        the python version or vllm version changes incompatibly:
            sudo rm -rf /var/lib/vllm/venv
        and the next service start will rebuild.
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/lib/vllm";
      description = ''
        Directory where Hugging Face caches models. Persistent across
        reboots so we don't re-download multi-GB shards on every restart.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "vllm";
      description = "System user that runs the vLLM services.";
    };

    group = mkOption {
      type = types.str;
      default = "vllm";
      description = "System group for the vLLM services.";
    };

    huggingfaceTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/hf-token";
      description = ''
        Path to a file containing a Hugging Face token. Required for
        gated models (Llama, Gemma, etc.). The file should contain ONLY
        the token, no shell prefix. Use sops-nix or agenix to manage it.
      '';
    };

    services = mkOption {
      type = types.attrsOf (types.submodule serviceOpts);
      default = { };
      description = "Map of service name → vLLM model configuration.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open the TCP ports for every configured vLLM service in the
        host firewall. Off by default since vLLM has NO authentication.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.cacheDir;
      createHome = true;
      description = "vLLM inference server";
      extraGroups = [ "video" ]; # GPU device access
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.cacheDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cacheDir}/huggingface 0755 ${cfg.user} ${cfg.group} -"
      # Parent of venvDir so uv can create the venv dir itself.
      "d ${builtins.dirOf cfg.venvDir} 0755 ${cfg.user} ${cfg.group} -"
      # vllm 0.10's multi-GPU `WorkerProc` calls
      # `subprocess.run(['/sbin/ldconfig', '-p'])` at worker init to
      # enumerate available shared libraries. NixOS doesn't ship
      # /sbin/ldconfig (it lives at $glibc/bin/ldconfig). Symlink it so
      # the hardcoded path resolves. `L+` = create symlink, replace.
      "L+ /sbin/ldconfig - - - - ${pkgs.glibc.bin}/bin/ldconfig"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      mapAttrsToList (_: svc: svc.port) cfg.services
    );

    systemd.services = mapAttrs' (
      name: svc:
      nameValuePair "vllm-${name}" {
        description = "vLLM inference server (${name}: ${svc.model})";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "nvidia-persistenced.service"
        ];
        wants = [
          "network-online.target"
          "nvidia-persistenced.service"
        ];

        # Triton JIT-compiles CUDA kernels at runtime and shells out to
        # a host C compiler (`cc`/`gcc` from PATH). systemd services
        # start with a near-empty PATH, so without this triton dies with
        # `Failed to find C compiler`. `path` *appends* to the default
        # systemd PATH (unlike `environment.PATH` which conflicts).
        path = [
          pkgs.gcc
          pkgs.binutils
        ];

        environment = {
          HOME = cfg.cacheDir;
          HF_HOME = "${cfg.cacheDir}/huggingface";
          # vllm 0.16 still respects TRANSFORMERS_CACHE for the tokenizer.
          TRANSFORMERS_CACHE = "${cfg.cacheDir}/huggingface";
          # Surface the proprietary NVIDIA driver's userspace libs onto
          # LD_LIBRARY_PATH. The vllm python wheel ships its own bundled
          # CUDA runtime + nvrtc + nvjitlink (under
          # `<wheel>/lib/python*/site-packages/nvidia/`), so we don't
          # need to link cudaPackages here. Linking nixpkgs `cudatoolkit`
          # would force a from-source CUDA build that fails inside the
          # nix sandbox without internet.
          #
          # `stdenv.cc.cc.lib` provides libstdc++.so.6, which PyTorch's
          # `_C` extension dlopen()s at import time. NixOS doesn't put
          # libstdc++ on the global library path, and pip-installed
          # wheels assume a standard FHS layout — so without this the
          # service crash-loops on `import torch`.
          # `zlib` covers a similar gap for several wheel deps.
          LD_LIBRARY_PATH = lib.makeLibraryPath [
            config.boot.kernelPackages.nvidia_x11
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];

          # Triton's runtime kernel JIT calls `/sbin/ldconfig -p` to
          # locate libcuda.so. NixOS has no /etc/ld.so.cache, so that
          # call exits non-zero and triton's worker bootstrap dies with
          # a CalledProcessError before any model can load. Pointing
          # TRITON_LIBCUDA_PATH at the nvidia_x11 lib dir lets triton
          # skip the ldconfig probe entirely. Required for any model
          # that hits triton kernels (e.g. Qwen3-Coder MoE → Mamba ops).
          TRITON_LIBCUDA_PATH = "${config.boot.kernelPackages.nvidia_x11}/lib";

          # Make triton's compiler choice explicit (it falls back to PATH
          # search otherwise — gcc is on PATH via systemd `path` above).
          CC = "${pkgs.gcc}/bin/gcc";
        }
        // svc.environment;

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.cacheDir;

          ExecStart = startScript name svc;

          # First model load can take 10+ minutes (download + compile).
          TimeoutStartSec = "30min";

          # Restart on crash but back off if it's a config error.
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 5;
          StartLimitIntervalSec = "10min";

          # Sandboxing — keep modest because we need GPU access.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          # cacheDir for HF model downloads, venvDir for uv's pip install.
          ReadWritePaths = [
            cfg.cacheDir
            cfg.venvDir
            (builtins.dirOf cfg.venvDir)
          ];
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = false; # nvidia driver may load modules
          ProtectControlGroups = true;
          # GPU access comes from `video` group membership (granted in
          # the user definition above), which gives /dev/nvidia* the
          # right perms via udev. Don't use DeviceAllow here: setting
          # it implicitly *denies* every other device, including
          # /dev/urandom and /dev/null which OpenSSL/Python need
          # — that breaks HF model downloads with weird EBUSY errors.

          # GPU compute can use a lot of file descriptors (NCCL, etc.)
          LimitNOFILE = 1048576;
        };
      }
    ) cfg.services;
  };
}
