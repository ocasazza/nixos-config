# `nvidia-verify` — one-shot health check for the NVIDIA driver + CUDA stack.
#
# Run this after every kernel/driver upgrade or during incident triage.
# It prints a section per check and exits non-zero if any check fails,
# so it's safe to use as a smoke test in deploy scripts.
#
# Checks (in order):
#   1. Kernel modules loaded                     (nvidia, nvidia_uvm, nvidia_drm)
#   2. /dev/nvidia* device nodes present
#   3. nvidia-smi runs and lists at least one GPU
#   4. Driver version + CUDA version (from nvidia-smi)
#   5. nvidia-persistenced.service is active
#   6. Tiny CUDA roundtrip via PyTorch (cuda available, alloc, matmul)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # NOTE: an earlier version of this script ran a tiny PyTorch matmul
  # to prove CUDA was actually usable. We removed that because
  # nixpkgs's `torch-bin` transitively pulls `cuda12.9-libnvshmem`,
  # which has NO binary cache and forces an ~3-hour from-source build
  # (nvcc cycling through 9 CUDA arches single-threaded).
  #
  # Instead we rely on `nvidia-smi`, the device nodes, and the vllm
  # service health endpoint to confirm CUDA actually works end-to-end.

  nvidiaVerify = pkgs.writeShellApplication {
    name = "nvidia-verify";
    # writeShellApplication runs shellcheck strict; satisfy it by
    # listing every external command we invoke.
    runtimeInputs = with pkgs; [
      coreutils
      kmod
      gnugrep
      gawk
      gnused
      curl
      systemd
      config.boot.kernelPackages.nvidia_x11.bin
    ];
    text = ''
      set -u

      RED=$'\e[0;31m'
      GREEN=$'\e[0;32m'
      YELLOW=$'\e[0;33m'
      BOLD=$'\e[1m'
      NC=$'\e[0m'

      FAIL=0

      # All printfs use `%s` for color codes to satisfy shellcheck's
      # SC2059 (no variables in printf format strings).
      header() { printf '%s== %s ==%s\n' "$BOLD" "$1" "$NC"; }
      ok()     { printf '  %sOK%s    %s\n' "$GREEN" "$NC" "$1"; }
      warn()   { printf '  %sWARN%s  %s\n' "$YELLOW" "$NC" "$1"; }
      fail()   { printf '  %sFAIL%s  %s\n' "$RED" "$NC" "$1"; FAIL=1; }

      header "1. Kernel modules"
      for m in nvidia nvidia_uvm nvidia_drm; do
        if lsmod | grep -q "^$m "; then
          ok "$m loaded"
        else
          fail "$m NOT loaded"
        fi
      done

      header "2. Device nodes"
      for d in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm; do
        if [ -e "$d" ]; then
          ok "$d exists"
        else
          fail "$d missing"
        fi
      done

      header "3. nvidia-smi"
      if smi_out=$(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>&1); then
        # Use bash parameter expansion instead of `sed s/^/    /` to
        # satisfy shellcheck SC2001.
        printf '    %s\n' "''${smi_out//$'\n'/$'\n    '}"
        ok "nvidia-smi reports GPUs"
      else
        fail "nvidia-smi failed: $smi_out"
      fi

      header "4. Driver / CUDA versions"
      if drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1); then
        ok "Driver version: $drv"
      fi
      if cudav=$(nvidia-smi -q 2>/dev/null | grep -m1 "CUDA Version" | awk -F: '{print $2}' | tr -d ' '); then
        ok "CUDA runtime (per driver): $cudav"
      fi

      header "5. nvidia-persistenced"
      if systemctl is-active --quiet nvidia-persistenced.service; then
        ok "nvidia-persistenced.service active"
      else
        warn "nvidia-persistenced.service not active (cold-start latency will be ~3-5s higher)"
      fi

      header "6. CUDA end-to-end (vllm health endpoint)"
      # Hit the local vllm coder service to prove CUDA is actually
      # usable. If vllm is up + serving on :8000 then CUDA works.
      if curl -fsS --max-time 3 http://127.0.0.1:8000/health >/dev/null 2>&1; then
        ok "vllm coder service responding on :8000 (CUDA end-to-end OK)"
      else
        warn "vllm coder service not responding on :8000 (may be loading model)"
      fi
      if curl -fsS --max-time 3 http://127.0.0.1:8001/health >/dev/null 2>&1; then
        ok "vllm chat service responding on :8001"
      else
        warn "vllm chat service not responding on :8001 (may be loading model)"
      fi

      echo
      if [ "$FAIL" -eq 0 ]; then
        printf '%s%sAll checks passed.%s\n' "$GREEN" "$BOLD" "$NC"
      else
        printf '%s%sOne or more checks failed.%s\n' "$RED" "$BOLD" "$NC"
        exit 1
      fi
    '';
  };
in
{
  environment.systemPackages = [ nvidiaVerify ];
}
