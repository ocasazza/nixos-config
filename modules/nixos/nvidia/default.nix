# NVIDIA driver + CUDA stack for RTX 3090 Ti (GA102, Ampere SM 8.6).
#
# The 3090 Ti is fully supported by the proprietary `production` driver.
# We do NOT use the `open` kernel modules — those require Turing or later
# but the open driver source still has stability issues for compute
# workloads as of nvidia 580.x. Stick with the closed-source binary.
#
# This module:
#   - loads `nvidia` kernel modules
#   - adds nvidia-drm KMS (required for Wayland/Sway compositing)
#   - turns on nvidia-persistenced (keeps GPU initialized between jobs;
#     drops cold-start latency for vLLM by ~3-5s and is required for
#     the GPU to honor PowerLimit/Pstate hints across reboots)
#   - exposes the userspace stack: `nvidia-smi`, NVML, CUDA runtime
#   - makes pkgs.cudaPackages available via `cudaSupport = true`
#     (only on hosts that import this module — kept narrow to avoid
#     globally rebuilding the world for non-GPU machines)
#
# Verify after activation:
#   sudo nixos-rebuild switch --flake '.#luna'
#   nvidia-smi                          # should list "NVIDIA GeForce RTX 3090 Ti"
#   nvidia-smi -q | grep "Driver Version"
#   nix-shell -p cudaPackages.cuda_nvcc --run 'nvcc --version'
{
  config,
  pkgs,
  ...
}:

{
  # Allow unfree (NVIDIA driver). Already set globally, but be explicit.
  nixpkgs.config.allowUnfree = true;

  # NOTE: do NOT set `nixpkgs.config.cudaSupport = true` here.
  # Flipping that globally invalidates the cache.nixos.org binary
  # cache for every CUDA-touching package (torch, opencv, etc.) and
  # forces rebuilds of CUDA 12.x from source — which fails inside
  # the nix sandbox because it tries to curl github mid-build.
  #
  # The packages that actually need CUDA (vllm, our nvidia-verify
  # PyTorch probe) get CUDA via their bundled runtime wheels +
  # LD_LIBRARY_PATH pointing at the proprietary driver in
  # `boot.kernelPackages.nvidia_x11`. That gives us cached binaries
  # AND working CUDA.

  # nvidia-drm needs KMS for any compositor (Sway, Hyprland, gdm-wayland).
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Steam, Wine, etc.
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required for Wayland and to use nvidia-drm.fbdev=1.
    modesetting.enable = true;

    # Use the proprietary kernel module (NOT the open one). The 3090 Ti
    # works on either, but the closed driver still has fewer regressions
    # for compute / vLLM / CUDA graphs as of 580.
    open = false;

    # Userspace utilities (nvidia-smi, nvidia-settings, NVML).
    nvidiaSettings = true;

    # Pin to the production branch — it tracks the latest stable
    # driver that has shipped CUDA binaries on the cache.
    package = config.boot.kernelPackages.nvidiaPackages.production;

    # Power management. Suspend/resume is unreliable on RTX 30xx desktop
    # cards; powerManagement.enable adds nvidia-suspend.service which
    # works around most of it. finegrained is for hybrid Optimus laptops
    # (Intel iGPU + nvidia dGPU) — leave OFF on a desktop with only the
    # discrete card.
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    # Keep the GPU initialized between CUDA contexts. This is what
    # `nvidia-persistenced` was designed for. Without it, every fresh
    # CUDA process pays a ~3-5s init cost (worse for big VRAM cards)
    # and the GPU drops back to P8 idle clocks aggressively.
    nvidiaPersistenced = true;
  };

  # Userspace tooling on PATH for debugging / verification.
  # Avoid `cudatoolkit` / `cudaPackages.cuda_*` here — they trigger the
  # CUDA-from-source rebuild path. Avoid `nvtopPackages.nvidia` for
  # the same reason (it transitively pulls `cuda-merged-12.9`).
  #
  # If you need:
  #   * nvcc:    `nix shell nixpkgs#cudaPackages.cuda_nvcc`
  #   * nvtop:   `nix shell nixpkgs#nvtopPackages.nvidia`
  # ad-hoc shells work fine (one-off build), but baking those into
  # the system closure would re-download/recompile a few GB.
  environment.systemPackages = with pkgs; [
    # nvidia-smi, nvidia-settings come from the driver package
    # automatically. These are extras for video-decode debugging.
    libva-utils # vainfo — verify NVDEC/NVENC via VA-API
  ];

  # Container GPU access (podman/docker --gpus all). Disabled by
  # default because enabling it pulls `cuda-merged-12.9` (~5GB) into
  # the system closure for the CDI generator. vllm runs as a systemd
  # service in this config — no containers needed. Re-enable when you
  # actually want to run ollama/openwebui/etc. in podman.
  hardware.nvidia-container-toolkit.enable = false;

  # NOTE: `EXTRA_LDFLAGS = "-L${pkgs.cudatoolkit}/lib"` would be nice
  # for ad-hoc builds, but referencing `cudatoolkit` triggers the
  # source rebuild path. The vllm systemd service sets its own
  # LD_LIBRARY_PATH (see modules/nixos/vllm/default.nix) using the
  # already-cached `nvidia_x11` driver libs, so we don't need a
  # global override here.

  # NOTE: sway is launched via greetd in the per-host system file
  # (`tuigreet --cmd sway`) and configured at the home-manager level,
  # not via `programs.sway.enable`. If you need `--unsupported-gpu`,
  # change the greetd command in your host's system/<host>/default.nix:
  #     command = "${tuigreet} --time --remember --cmd 'sway --unsupported-gpu'";
  # Modern sway+nvidia-drm KMS works without it for the 3090 Ti, so we
  # leave it off by default.
}
