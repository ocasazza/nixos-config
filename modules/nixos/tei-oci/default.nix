# Text Embeddings Inference (TEI) as an OCI container (podman).
#
# Why this module exists (and why it replaces the vLLM embedding path
# long-term):
#   * The current `local.vllm.services.embedding` hosts Qwen3-Embedding-0.6B
#     under vLLM 0.10 via `--task embed`. vLLM *works* as an embedding
#     server, but it's architecturally wasteful for pooling models:
#     vLLM allocates a full KV cache (driven by `gpuMemoryUtilization`
#     and `maxModelLen`) even for pooling — see upstream issue
#     vllm-project/vllm#29584. Embedding / pooling has no autoregressive
#     decode loop, so the KV blocks are never populated; they just sit
#     there eating VRAM.
#   * HuggingFace's `text-embeddings-inference` (TEI) is purpose-built
#     for this workload: Rust server + candle / flash-attention inference,
#     batched padded inference, NO KV cache at all, exposes both a native
#     `/embed` endpoint and an OpenAI-compatible `/v1/embeddings` endpoint
#     on the same port. Memory footprint is ~the model weights plus a
#     small activation scratch — roughly 1/4–1/3 of what vLLM was using.
#   * TEI isn't packaged from source in nixpkgs (it pulls in a giant
#     candle / pytorch / CUDA tree), so we run it as an OCI container
#     from upstream's published image `ghcr.io/huggingface/text-embeddings-
#     inference`. Same podman path as `modules/nixos/tikv-oci/`.
#
# Why OCI-containers (podman) vs. nixpkgs-from-source:
#   * As above — TEI's upstream build graph isn't in nixpkgs. Upstream
#     publishes multi-arch CUDA images on GHCR; `ghcr.io/huggingface/
#     text-embeddings-inference:cuda-1.9` is the current CUDA flavor
#     (tag `cuda-<major>.<minor>`, updated roughly on TEI release cadence).
#   * podman + `virtualisation.oci-containers` gives us a real systemd
#     unit (`podman-tei-server.service`) with declarative ExecStart,
#     bind mounts, GPU passthrough via CDI or `--gpus`, and no extra
#     ceremony. This repo's tikv-oci module is the precedent.
#
# GPU passthrough — CDI vs. `--gpus`:
#   * Podman 4.4+ supports NVIDIA via the Container Device Interface
#     (CDI). `--device nvidia.com/gpu=0` is the modern, declarative form
#     and requires nvidia-container-toolkit to have generated a CDI spec
#     (`/etc/cdi/nvidia.yaml`).
#   * `--gpus device=0` is the Docker-style fallback; podman also
#     accepts it but routes through nvidia-container-runtime.
#   * Verify which is available on luna with `podman info | grep -i cdi`
#     (CDI spec dir should be listed, and `ls /etc/cdi/` should contain
#     `nvidia.yaml`). We default to the CDI form below since luna has
#     the nvidia modules configured; swap to the `--gpus` form by
#     overriding `extraOptions` if CDI isn't set up.
#
# Coexistence with `local.vllm.services.embedding`:
#   * vLLM's embedding service is currently on port 8002. To avoid
#     collision, this module defaults to port 8003 so both can run
#     in parallel during migration.
#   * LiteLLM's `embedding` model group (projects/swarm/litellm_config.yaml)
#     currently points at `http://localhost:8002/v1` with
#     `model: openai/Qwen/Qwen3-Embedding-0.6B`. Once you flip
#     `local.vllm.services.embedding` off and enable this module,
#     update that entry to:
#       api_base: http://localhost:${cfg.port}/v1    (default 8003)
#       model:    openai/Qwen/Qwen3-Embedding-0.6B   (TEI exposes an
#                                                     OpenAI-compatible
#                                                     /v1/embeddings
#                                                     surface; the
#                                                     model id is a
#                                                     pass-through
#                                                     label.)
#     Alternatively, reassign `cfg.port = 8002` after vLLM-embedding is
#     disabled, and leave LiteLLM config untouched.
#
# Networking posture: default is loopback-only (publish on 127.0.0.1),
# matching the existing vLLM-embedding service. Flip `openFirewall =
# true` to bind 0.0.0.0 and open the host firewall for LAN access.
# TEI ships no auth — loopback is the safe default.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.local.teiOci;

  bindHost = if cfg.openFirewall then "0.0.0.0" else "127.0.0.1";

  # Render GPU indices ([0], [0 1], ...) into per-device podman flags.
  # CDI form: `--device nvidia.com/gpu=<idx>` (repeatable). The
  # nvidia-container-toolkit CDI spec names devices `nvidia.com/gpu=<idx>`
  # for each physical GPU plus `nvidia.com/gpu=all`.
  gpuCdiFlags = concatMap (idx: [
    "--device"
    "nvidia.com/gpu=${toString idx}"
  ]) cfg.gpuDevices;
in
{
  options.local.teiOci = {
    enable = mkEnableOption ''
      HuggingFace text-embeddings-inference (TEI) running as an OCI
      container (podman). Loads a HF embedding model (default:
      Qwen/Qwen3-Embedding-0.6B) and serves both the native `/embed`
      API and an OpenAI-compatible `/v1/embeddings` endpoint. This is
      the "correct long-term" replacement for the vLLM-based
      `local.vllm.services.embedding` path, which allocates a full KV
      cache even for pooling models (upstream vllm#29584).

      Default port is 8003 so this can run in parallel with the vLLM
      embedding service on 8002 during migration
    '';

    image = mkOption {
      type = types.str;
      default = "ghcr.io/huggingface/text-embeddings-inference:cuda-1.9";
      description = ''
        Full OCI image reference for TEI. Upstream publishes CUDA images
        on GHCR tagged `cuda-<major>.<minor>`. `cuda-1.9` is the current
        pin at time of module authoring; bump to match upstream TEI
        releases. Podman pulls with `--pull missing` on unit start
        (the oci-containers module default), so changing this triggers
        a re-pull on next `systemctl restart podman-tei-server`.
      '';
    };

    model = mkOption {
      type = types.str;
      default = "Qwen/Qwen3-Embedding-0.6B";
      description = ''
        HuggingFace repository id of the embedding model to serve.
        TEI downloads weights into `/data` inside the container on
        first start (bind-mounted to `cfg.dataDir` on the host), so
        subsequent restarts don't re-download. Must be a pooling /
        embedding model (TEI refuses generative-only models).
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8003;
      description = ''
        Host port to publish TEI on. Default is 8003 to avoid colliding
        with the existing `local.vllm.services.embedding` service on
        8002. When you're ready to swap (disable vLLM embedding, enable
        this), set `port = 8002` here so LiteLLM's `embedding` model
        group keeps working with its existing `api_base:
        http://localhost:8002/v1`. Alternatively, leave the port at
        8003 and update LiteLLM's config to match.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/tei-oci";
      description = ''
        Host directory bind-mounted into the container at `/data`. TEI
        uses `/data` as the HuggingFace cache (HF_HOME) so model
        downloads survive container recreations and nixos-rebuilds.
        Wipe to force a fresh download.
      '';
    };

    gpuDevices = mkOption {
      type = types.listOf types.int;
      default = [ 0 ];
      description = ''
        List of physical GPU indices to hand to TEI. On luna:
          0 — RTX 3090 Ti (24 GiB)  [default]
          1 — RTX 4000 SFF Ada (20 GiB)
        Qwen3-Embedding-0.6B is small enough that a single 3090 Ti
        slot is overkill; keep it pinned to GPU 0 by default so the
        RTX 4000 remains dedicated to the vLLM coder tensor-parallel
        shard. Passed as repeated `--device nvidia.com/gpu=<idx>`
        flags (CDI form).
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open TEI's port on the host firewall AND bind on 0.0.0.0
        instead of 127.0.0.1. Off by default — TEI ships no auth;
        loopback-only is the safe posture and matches the existing
        vLLM-embedding service.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Use the same podman backend as tikv-oci. luna already sets
    # `virtualisation.podman.enable = true`; this just selects which
    # runtime the oci-containers module shells out to.
    virtualisation.oci-containers.backend = mkDefault "podman";

    # Create the bind-mount target before unit start so podman doesn't
    # auto-create it with the wrong owner/mode. HF cache writes happen
    # as the container's default user (root inside the TEI image), so
    # root:root 0750 on the host is fine.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    virtualisation.oci-containers.containers.tei-server = {
      image = cfg.image;

      # Passed after the image entrypoint (`text-embeddings-router`).
      # `--hostname 0.0.0.0` binds inside the container; the `ports`
      # mapping below scopes the host-side publish to loopback or LAN.
      cmd = [
        "--model-id"
        cfg.model
        "--port"
        (toString cfg.port)
        "--hostname"
        "0.0.0.0"
      ];

      # HF_HOME=/data — belt-and-suspenders. TEI already defaults to
      # `/data` for its cache via its own env var, but setting HF_HOME
      # explicitly covers any code path that checks the standard HF
      # environment variable instead.
      environment = {
        HF_HOME = "/data";
      };

      volumes = [
        "${cfg.dataDir}:/data"
      ];

      # GPU passthrough via CDI (`--device nvidia.com/gpu=<idx>`). This
      # is the modern podman-4.4+ form; requires nvidia-container-toolkit
      # to have generated `/etc/cdi/nvidia.yaml`. If CDI isn't set up on
      # this host, override `extraOptions` to the Docker-style form,
      # e.g. [ "--gpus=device=0" ]. Verify with:
      #   podman info | grep -i cdi
      #   ls /etc/cdi/
      extraOptions = gpuCdiFlags;

      # Loopback-only by default. With openFirewall=true, bind 0.0.0.0
      # to expose on the LAN. The `ports` mapping is `<host-ip>:<host-
      # port>:<ctr-port>` — same port on both sides since TEI doesn't
      # care about host vs. container port separation here.
      ports = [
        "${bindHost}:${toString cfg.port}:${toString cfg.port}"
      ];
    };
  };
}
