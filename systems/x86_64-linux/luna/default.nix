{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

# luna — desktop NixOS box on the home LAN (192.168.1.57).
#
# Hardware: RTX 3090 Ti (24GB), Intel CPU.
# Role: GPU host for vLLM inference + general workstation.
#
# This file is the single source of truth for luna. Snowfall auto-imports
# every module under `modules/nixos/` (cachix, claude-code, nvidia,
# nvidia-verify, vllm, etc.); we just configure their options below.
#
#      the home directory if the migration hasn't happened yet.

let
  user = lib.salt.user;

  # Authorized SSH keys for casazza + root. Both keys are recognized:
  #   * id_ed25519 — this Mac (casazza@MacBook-Air)
  #   * olive_id_ed25519 — the personal "olive" key shared across the
  #     home LAN (seir, contra, mm0x, hp0x). Keeping it lets the
  #     existing fleet tooling continue to reach luna.
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs1Mxt1lJQ4Ij5po+sY81YkEQIl0/GX22ZPYJFPMuWf casazza@MacBook-Air"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPMkn0A3SaiXd0GLc25puPLqSSw9M7WGs0CVcyvZZYm9 olive@casazza.info"
  ];

  tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
in
{
  imports = [
    ../../../modules/shared
    ../../../modules/shared/cachix
  ];

  # disko spec: snapshot of luna's existing partitions on nvme1n1
  # (system) + nvme0n1 (scratch btrfs) + sda/sdb (mdadm RAID1).
  # The module itself lives at `modules/nixos/disk-config/` and is
  # auto-discovered by snowfall, but its config is gated behind this
  # opt-in so no other NixOS host inherits luna's disk spec.
  local.lunaDisk.enable = true;

  # NOTE: home-manager wiring is handled by snowfall via the snowfall
  # home at `homes/x86_64-linux/casazza@luna/default.nix`.

  # ── boot ─────────────────────────────────────────────────────────────
  # disk-config.nix declares fileSystems/swapDevices via disko; we just
  # set bootloader + kernel modules here.
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 42;
      };
      efi.canTouchEfiVariables = true;
    };

    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "rtsx_pci_sdmmc"
    ];

    kernelModules = [
      "kvm-intel"
      "uinput"
      "tun"
    ];

    kernelPackages = pkgs.linuxPackages_latest;
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  # ── network ──────────────────────────────────────────────────────────
  networking = {
    hostName = "luna";
    usePredictableInterfaceNames = true;
    networkmanager.enable = true;
    useDHCP = false;
  };

  # ── nix ──────────────────────────────────────────────────────────────
  nix = {
    nixPath = [ "nixos-config=/home/${user.name}/.local/share/src/nixos-config:/etc/nixos" ];
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings = {
      allowed-users = [ "${user.name}" ];
      # `casazza` listed as trusted-user so the Macs can use luna as a
      # remote builder via `ssh-ng://casazza@luna.local` (see
      # `modules/shared/distributed-builds/`). Without this, `nix store
      # info --store ssh-ng://casazza@luna.local` reports `Trusted: 0`
      # and the daemon refuses to accept arbitrary nars from the
      # client.
      trusted-users = [
        "root"
        "${user.name}"
      ];
      auto-optimise-store = true;
      substituters = [ "https://nix-community.cachix.org" ];
      trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
    };
  };

  # ── programs ─────────────────────────────────────────────────────────
  programs = {
    dconf.enable = true;
    zsh.enable = true;

    # nix-ld provides /lib64/ld-linux-x86-64.so.2 so generic-linux ELF
    # binaries (e.g. the `ptxas` shipped inside the triton pip wheel that
    # vllm uses for CUDA kernel JIT) can launch on NixOS. Without this,
    # vllm-coder workers crash during torch.compile with exit 127:
    #   Could not start dynamically linked executable: …/triton/.../ptxas
    # The `libraries` list mirrors NixOS's standard FHS-compat set so any
    # downstream binary loaded via nix-ld finds typical glibc/openssl/zlib.
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        glibc
      ];
    };
  };

  # ── services ─────────────────────────────────────────────────────────
  services = {
    dbus.enable = true;
    openssh.enable = true;
    # Open SSH port (22) for remote builders and SSH access.
    # Luna acts as a remote builder for darwin hosts and needs to be reachable.
    networking.firewall.allowedTCPPorts = [ 22 ];
    gnome.gnome-keyring.enable = true;
    hardware.bolt.enable = true;
    # Avahi/mDNS: publish luna as `luna.local` on the LAN so any host
    # (Mac, Linux, browser via Bonjour) can hit
    # http://luna.local:8000  →  vllm coder OpenAI-compatible API
    # http://luna.local:8001  →  vllm chat OpenAI-compatible API
    # without static DNS. This is the user-facing requirement.
    avahi = {
      enable = true;
      nssmdns4 = true; # let glibc resolve *.local through avahi
      ipv4 = true;
      ipv6 = true;
      openFirewall = true; # UDP 5353 mDNS port
      publish = {
        enable = true;
        addresses = true; # publish A/AAAA records for luna.local
        workstation = true; # show up in Mac Finder / Bonjour browsers
        domain = true;
        hinfo = true;
      };
      # Advertise the vllm endpoints over mDNS-SD so service-aware
      # clients (Open WebUI mDNS, etc.) auto-discover them.
      extraServiceFiles = {
        vllm-coder = ''
          <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">vllm-coder on %h</name>
            <service>
              <type>_http._tcp</type>
              <port>8000</port>
              <txt-record>path=/v1</txt-record>
              <txt-record>model=Qwen/Qwen2.5-Coder-32B-Instruct-AWQ</txt-record>
            </service>
          </service-group>
        '';
        vllm-chat = ''
          <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">vllm-chat on %h</name>
            <service>
              <type>_http._tcp</type>
              <port>8001</port>
              <txt-record>path=/v1</txt-record>
              <txt-record>model=Qwen/Qwen2.5-3B-Instruct</txt-record>
            </service>
          </service-group>
        '';
      };
    };

    # NO upower / NO tlp — luna is a always-on workstation, not a
    # laptop. tlp aggressively park-disables NVMe/USB/PCI devices on
    # idle, which is wrong for a 24/7 GPU host.
    upower.enable = false;
    tlp.enable = false;
    thermald.enable = true;

    # Ignore every event that could trigger a suspend at the logind
    # level. Lid switches are no-ops (luna might be a closed laptop or
    # has a hotplug-able monitor); power/suspend/hibernate keys do
    # nothing; no idle-based action.
    logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandlePowerKey = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      IdleAction = "ignore";
      IdleActionSec = "0";
    };

    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${tuigreet} --time --remember --cmd sway";
          user = "greeter";
        };
      };
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };

  systemd = {
    services = {
      greetd.serviceConfig = {
        Type = "idle";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal"; # without this errors will spam on screen

        # without these bootlogs will spam on screen
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };
    };

    # Belt-and-braces: mask every systemd target that could trigger
    # a suspend / hibernate / sleep / hybrid-sleep transition. Even if
    # GNOME/sway/`systemctl suspend` were invoked, systemd refuses.
    targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      "hybrid-sleep".enable = false;
    };
  };

  # ── never sleep ──────────────────────────────────────────────────────
  # Workstation, not a laptop. Anything that could suspend is off:
  #   * powerManagement.enable      = false → no APM/ACPI suspend hooks
  #   * powerManagement.cpuFreqGovernor = performance → no idle downclock
  #     (still respects thermald clamps)
  powerManagement = {
    enable = false;
    cpuFreqGovernor = "performance";
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    config = {
      sway = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
  };

  # ── hardware ─────────────────────────────────────────────────────────
  # GPU/CUDA bits live in `modules/nixos/nvidia/` (auto-imported by
  # snowfall). This block only handles the non-GPU bits.
  #
  # NOTE: `enableAllFirmware = true` would drag in `facetimehd-calibration`
  # (Apple FaceTime HD camera firmware, x86_64-linux package) which
  # requires curl-fetching a calibration blob during build that's
  # unreachable inside the nix sandbox without internet. We use the
  # narrower `enableRedistributableFirmware` instead, which covers
  # every non-Apple firmware blob luna actually needs (NVIDIA, Intel
  # microcode, WiFi, etc.).
  hardware = {
    enableRedistributableFirmware = true;
    brillo.enable = true; # brightness
  };

  virtualisation = {
    containers.enable = true;

    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # ── users ────────────────────────────────────────────────────────────
  # Keep mutableUsers=true (the default) so the existing `olive` user
  # isn't purged on first switch — if you later want to clean up:
  #   sudo userdel olive
  #   sudo rm -rf /home/olive   # only after migration completes
  users.mutableUsers = true;

  users.users = {
    ${user.name} = {
      isNormalUser = true;
      description = "Olive Casazza";
      extraGroups = [
        "wheel" # sudo
        "networkmanager"
        "video" # hotplug devices, thunderbolt, GPU
        "dialout" # TTY access
        "audio"
        #"docker"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = keys;

      # No declarative password. `mutableUsers = true` leaves the live
      # login password under `passwd` control; an `initialPassword`
      # default would leak plaintext into /nix/store without taking
      # effect on an already-provisioned box. Interactive password
      # (if needed as SSH-key fallback) is set out-of-band via
      # `passwd` on first login.
    };

    root = {
      openssh.authorizedKeys.keys = keys;
    };
  };

  security.sudo = {
    enable = true;
    extraConfig = ''
      # Passwordless sudo for the canonical user (casazza) and the
      # legacy installer user (olive). olive's rule disappears once
      # the user is removed; until then keep it so cast-on / remote
      # rebuilds work unattended during migration.
      ${user.name} ALL=(ALL) NOPASSWD: ALL
      olive ALL=(ALL) NOPASSWD: ALL
    '';
    extraRules = [
      {
        commands = [
          {
            command = "${pkgs.systemd}/bin/reboot";
            options = [ "NOPASSWD" ];
          }
        ];
        groups = [ "wheel" ];
      }
    ];
  };

  # ── one-shot olive -> casazza home seed ────────────────────────────
  # The installer created `/home/olive`. Our config declares
  # `casazza`. NixOS will create an empty `/home/casazza` for the new
  # user; this activation script seeds it from `/home/olive` (cp -a,
  # not mv) so olive keeps working in parallel during transition.
  #
  # Idempotent: only runs the seed when /home/casazza is empty.
  # After you're done with olive, manually:
  #   sudo userdel olive && sudo rm -rf /home/olive
  system.activationScripts.seedCasazzaHome = {
    deps = [ "users" ];
    text = ''
      if [ -d /home/olive ] && [ -d /home/${user.name} ] && [ -z "$(ls -A /home/${user.name} 2>/dev/null)" ]; then
        echo "Seeding /home/${user.name} from /home/olive"
        ${pkgs.coreutils}/bin/cp -a /home/olive/. /home/${user.name}/
        ${pkgs.coreutils}/bin/chown -R ${user.name}:users /home/${user.name} || true
      fi
    '';
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    jetbrains-mono
    font-awesome
  ];

  environment.systemPackages = with pkgs; [
    gitFull
    inetutils
    pciutils # `lspci` — the installer image didn't include it
    usbutils # `lsusb`
    inputs.ghostty.packages.x86_64-linux.default
  ];

  # ── vLLM inference services ──────────────────────────────────────────
  # Single service: Qwen3-Coder-30B-A3B-Instruct (FP8) sharded across
  # BOTH GPUs via tensor parallelism.
  #
  # luna's GPUs:
  #   - PCI 55:00.0 — RTX 3090 Ti, 24 GiB  (nvidia-smi index 0)
  #   - PCI A2:00.0 — RTX 4000 SFF Ada, 20 GiB (nvidia-smi index 1)
  #   = 44 GiB combined VRAM
  #
  # Qwen3-Coder-30B-A3B-Instruct-FP8:
  #   - Mixture-of-Experts: 30B total, 3B active per token
  #   - FP8 quant ≈ 30 GiB on disk, ~32 GiB live across both cards
  #     (16 GiB per shard with KV cache + overhead)
  #   - Native FP8 kernels via vllm 0.10's marlin/cutlass paths
  #   - 256k native context length; we cap at 32k to keep KV cache sane
  #
  # Why one service across both GPUs (vs. one per GPU):
  #   - tensor-parallel-size=2 doubles throughput per request and
  #     unlocks the full 30B parameter count (otherwise we'd be capped
  #     at the smaller card's 20 GiB).
  #   - With CUDA_DEVICE_ORDER=PCI_BUS_ID both indices are stable
  #     across reboots so the sharding doesn't drift.
  #   - vllm handles uneven VRAM transparently — it shards by parameter
  #     count, not capacity, and uses the smaller card's headroom for
  #     KV cache.
  local.vllm = {
    enable = true;
    openFirewall = true;

    # vllmVersion default is 0.10.0 (Qwen3-Coder MoE support landed
    # in 0.10). Bumping this triggers the venv recreation logic in the
    # vllm module on next service start.

    # If you ever pin a gated model (Llama family, Gemma, etc.):
    #   1. Add a sops/agenix secret with your HF token
    #   2. Set huggingfaceTokenFile = config.sops.secrets.hf-token.path;
    # huggingfaceTokenFile = "/var/lib/vllm/.hf-token";

    services = {
      coder = {
        # Community AWQ build (4-bit weight-only quantization).
        #
        # Why AWQ instead of the official FP8 build:
        #   - The official `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8` uses
        #     vllm's CutlassBlockScaledGroupedGemm path for the MoE
        #     expert layer, which is Hopper-only (sm_90). luna's 3090 Ti
        #     is Ampere (sm_86); the Ada card is sm_89. With the FP8
        #     build the worker silently deadlocks during model load
        #     when the unsupported kernel is selected.
        #   - AWQ uses `awq_marlin` kernels, which originated on Ampere
        #     and have a fused-MoE expert path that runs on sm_8x.
        #   - 4-bit weights ≈ 16 GiB on disk → ~9 GiB per shard at tp=2,
        #     leaving ample KV cache headroom on both cards.
        model = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ";
        port = 8000;
        # Both cards used; tp=2 shards weights across them.
        tensorParallelSize = 2;
        # Dropped from 0.85 → 0.75 so GPU 0 (the 3090 Ti) has ~2 GiB of
        # headroom for the co-located `embedding` service below, which
        # pins itself to GPU 0 via CUDA_VISIBLE_DEVICES=0 and claims
        # gpuMemoryUtilization = 0.08 (~2 GiB on a 24 GiB card).
        #
        # Per-GPU allocation after this change:
        #   GPU 0 (3090 Ti, 24 GiB): ~18 GiB coder + ~2 GiB embedding
        #   GPU 1 (RTX 4000, 20 GiB): ~15 GiB coder (embedding not pinned here)
        #
        # AWQ is small enough (16 GiB total, ~8 GiB per shard at tp=2)
        # that even the reduced 0.75 leaves ample KV cache headroom.
        gpuMemoryUtilization = 0.75;
        # 32k is plenty for code agent workflows; the model supports
        # up to 256k natively but KV cache memory scales linearly with
        # context length. Bump higher if you hit context limits.
        maxModelLen = 32768;
        # cpatonn's AWQ build is wrapped in `compressed-tensors` format
        # (the modern unified quant container). vLLM auto-detects this
        # from quant_config.json and dispatches to the marlin kernel
        # internally, so DON'T pass `--quantization awq_marlin` — that
        # mismatches the config's declared method and trips a pydantic
        # validation error during engine init.
        environment = {
          # PCI_BUS_ID order so the 3090 Ti (faster) is rank 0 and the
          # RTX 4000 (slower) is rank 1 — vllm prefers rank 0 for the
          # scheduler/CPU side, which avoids a perf cliff.
          CUDA_DEVICE_ORDER = "PCI_BUS_ID";
          CUDA_VISIBLE_DEVICES = "0,1";
          # vllm 0.10 NCCL needs an explicit interface for intra-host
          # GPU comms when multiple network interfaces are present;
          # `lo` is sufficient for single-host tensor parallel.
          NCCL_SOCKET_IFNAME = "lo";
          NCCL_P2P_DISABLE = "0"; # let NCCL use direct P2P over PCIe
        };
      };

      # ── embedding service ─────────────────────────────────────────
      # Qwen3-Embedding-0.6B — small FP16 embedding model (~1.3 GiB on
      # disk) co-located on GPU 0 alongside the coder shard. Powers:
      #   - LocalGPT's "find related notes" inside Obsidian
      #   - Semantic vault search from swarm MCP tools
      #   - Open WebUI Knowledge RAG quality (real embeddings, not the
      #     default sentence-transformers CPU fallback)
      #
      # vllm 0.10 turns any model into a pooling/embedding server via
      # `--task embed` (converts the generative head into a pooling
      # head). See upstream pooling_models docs for details.
      #
      # Pinned to GPU 0 only — tensor-parallel on a 0.6B model is pure
      # overhead; a single shard on the 3090 Ti easily beats any
      # cross-GPU comms cost, and it frees the RTX 4000 to dedicate its
      # full remaining VRAM to the coder shard's KV cache.
      embedding = {
        model = "Qwen/Qwen3-Embedding-0.6B";
        port = 8002;
        # ~2 GiB on a 24 GiB 3090 Ti. FP16 weights are ~1.3 GiB; the
        # remainder is KV/pooling scratch. Keep tight since coder is
        # holding the bulk of GPU 0.
        gpuMemoryUtilization = 0.08;
        # 2048 stays safely under the ~3472 KV-cache ceiling vllm
        # computes at util 0.08 on GPU 1 (~0.37 GiB KV after coder's
        # tp=2 shard takes its bite). Embedding workloads typically
        # chunk at 512-1024 tokens, so 2K is still ample.
        maxModelLen = 2048;
        # vllm 0.10 serves embedding models via `--task embed`. Without
        # this flag vllm tries to load Qwen3-Embedding as a generative
        # model, which fails because the HF config declares it as a
        # pooling model (no LM head).
        # `--enforce-eager` skips torch.compile + CUDA-graph capture
        # (saves ~200-500 MiB at cold start, unblocks OOM when coder's
        # tp=2 shard already claims 21 GiB on GPU 0).
        # `--max-num-seqs 1` caps concurrency so per-seq KV blocks don't
        # balloon past the 0.69 GiB budget.
        extraArgs = [
          "--task"
          "embed"
          "--enforce-eager"
          "--max-num-seqs"
          "1"
        ];
        environment = {
          # Stable device ordering + pin to GPU 1 (RTX 4000 SFF Ada).
          # GPU 0 (3090 Ti) is saturated by coder at util 0.75 plus
          # ~1.25 MiB free; moving embedding to GPU 1 decouples the
          # two services. GPU 1 has ~5 GiB free after coder's tp=2
          # shard — plenty for a 0.6B embedding + 4K KV.
          CUDA_DEVICE_ORDER = "PCI_BUS_ID";
          CUDA_VISIBLE_DEVICES = "1";
        };
      };
    };
  };

  # ── open-webui ───────────────────────────────────────────────────────
  # Browser-based chat frontend for the local vLLM endpoint(s). Backend
  # URLs auto-derive from `local.vllm.services` above, so adding an
  # embedding/chat service later wires it into the UI on next switch.
  #
  # Fully declarative wiring:
  #   * Admin account seeded from `secrets/openwebui-admin-password.yaml`
  #     via upstream's `WEBUI_ADMIN_EMAIL` / `WEBUI_ADMIN_PASSWORD` env
  #     vars (the module renders a sops-backed env file and hands it to
  #     `services.open-webui.environmentFile`).
  #   * JWT signing pinned to the sops-held `WEBUI_SECRET_KEY` so tokens
  #     survive rebuilds.
  #   * Ingest-pipeline API token pinned into the admin's `api_key` row
  #     by a post-start oneshot. Upstream has no `DEFAULT_USER_API_KEY`
  #     env var, so this is declarative-by-wrapping-imperative — every
  #     rebuild UPSERTs the same row into sqlite. See the module's
  #     `seedScript` and the commit introducing it for the rationale.
  #
  # Verify (after rebuild):
  #   curl -sS http://luna.local:8080/health
  #   curl -sS \
  #     -H "Authorization: Bearer $(sudo cat /run/secrets/openwebui-api-token)" \
  #     http://luna.local:8080/api/v1/knowledge/
  local.openWebUI = {
    enable = true;
    openFirewall = true;

    admin = {
      email = "admin@luna.local";
      name = "Luna Admin";
      passwordFile = config.sops.secrets.openwebui-admin-password.path;
      secretKeyFile = config.sops.secrets.openwebui-secret-key.path;
      apiKeyFile = config.sops.secrets.openwebui-api-token.path;
    };
  };

  # ── MCPO (MCP-to-OpenAPI proxy for Open WebUI) ───────────────────────
  # Exposes local stdio MCP servers over HTTP so Open WebUI's Tools
  # registry can pick them up. Currently serves the Obsidian vault
  # (read-only) via @bitbonsai/mcpvault under npx — a direct-filesystem
  # MCP server that reads vault files straight off disk (no Obsidian
  # desktop app / Local REST API plugin required, which is the right
  # shape for a headless host).
  #
  # After nixos-rebuild:
  #   curl http://luna.local:8100/obsidian/openapi.json | jq .info
  #
  # Then wire it into Open WebUI (one-time, admin UI — Open WebUI has
  # no declarative tool-server option in its NixOS module):
  #   Admin → Settings → Tools → Add tool server
  #     URL:  http://luna.local:8100/obsidian
  #     Name: Obsidian
  #
  # Add more MCP servers by appending to `local.mcpo.servers`; each
  # entry gets its own URL path (e.g. `/obsidian`, `/github`, etc.).
  local.mcpo = {
    enable = true;
    openFirewall = true;
    port = 8100;

    servers = {
      obsidian = {
        command = "npx";
        # @bitbonsai/mcpvault takes the vault path as a positional
        # argument; no env vars required.
        args = [
          "-y"
          "@bitbonsai/mcpvault@latest"
          "/home/casazza/obsidian/vault"
        ];
      };
    };
  };

  # mcpo runs under `ProtectHome = true`, so /home is hidden from the
  # unit's mount namespace. Bind the vault in read-only to give the
  # Obsidian MCP child read access without exposing the rest of $HOME.
  # Read-only at the namespace level is the canonical "no-writes"
  # guardrail — @bitbonsai/mcpvault exposes write_note/delete_note/etc.
  # on the MCP surface, but the bind-mount prevents those from actually
  # touching disk. The swarm's Python agent also allow-lists only the
  # read tools; this is belt-and-braces.
  systemd.services.mcpo.serviceConfig.BindReadOnlyPaths = [
    "/home/casazza/obsidian/vault"
  ];

  # ── observability ────────────────────────────────────────────────────
  # Local Prometheus + Grafana + node/GPU/vLLM scrapes. Module lives in
  # `modules/nixos/observability/`. Auto-discovers vllm services from
  # `local.vllm.services` so adding an embedding endpoint later wires
  # itself into the dashboard.
  #
  # After first deploy:
  #   * Grafana UI → http://luna.local:3000
  #     admin password: `sops decrypt secrets/grafana-admin-password.yaml`
  #   * Import dashboards by ID: 1860 (node), 14574 (NVIDIA GPU)
  #   * vLLM panels: build from /metrics — no canonical dashboard yet.
  local.observability = {
    enable = true;
    openFirewall = true;
    # adminPasswordFile is wrapped as `$__file{...}` inside Grafana's
    # config.ini by the observability module — Grafana re-reads the
    # file at service start, so rotation = edit the sops yaml + switch.
    grafana.adminPasswordFile = config.sops.secrets.grafana-admin-password.path;
  };

  # ── secrets (sops-nix) ───────────────────────────────────────────────
  # sops-nix decrypts `secrets/*.yaml` at activation using an age identity
  # derived from luna's SSH host key (default sshKeyPaths). The four ingest
  # secrets below are encrypted to *two* recipients in `.sops.yaml`:
  # the user's age key (for `sops edit` from darwin) and luna's
  # ssh-host-derived age key (for in-place decryption here with no
  # private-key copy). Placeholders (`REPLACE_ME_WITH_REAL_TOKEN`) ship
  # in the encrypted files; real values land later via
  # `sops edit secrets/<name>.yaml` from a machine holding the user key.
  sops = {
    defaultSopsFile = ../../../secrets/openwebui-api-token.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      openwebui-api-token = {
        sopsFile = ../../../secrets/openwebui-api-token.yaml;
        key = "openwebui_api_token";
        # Readable by the ingest service (which POSTs it as a bearer
        # token) and by root (which the open-webui-seed-api-key unit
        # runs as). DynamicUser=true on open-webui itself means we can't
        # simply own the file as `open-webui`; we route the same
        # plaintext into the seeder (runs as root) and the ingest sink
        # via distinct code paths instead.
        owner = "ingest";
        group = "ingest";
        mode = "0400";
      };
      openwebui-admin-password = {
        sopsFile = ../../../secrets/openwebui-admin-password.yaml;
        key = "openwebui_admin_password";
        # Referenced by sops.templates."open-webui.env" via the
        # placeholder mechanism; the rendered env file is the thing
        # systemd loads, not this file directly, so owner/mode here
        # is just the at-rest permission on /run/secrets/.
        owner = "root";
        group = "root";
        mode = "0400";
      };
      openwebui-secret-key = {
        sopsFile = ../../../secrets/openwebui-secret-key.yaml;
        key = "openwebui_secret_key";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      atlassian-email = {
        sopsFile = ../../../secrets/atlassian-email.yaml;
        key = "atlassian_email";
        owner = "ingest";
        group = "ingest";
        mode = "0400";
      };
      atlassian-api-token = {
        sopsFile = ../../../secrets/atlassian-api-token.yaml;
        key = "atlassian_api_token";
        owner = "ingest";
        group = "ingest";
        mode = "0400";
      };
      github-api-token = {
        sopsFile = ../../../secrets/github-api-token.yaml;
        key = "github_api_token";
        owner = "ingest";
        group = "ingest";
        mode = "0400";
      };

      # Bearer token luna presents to the GFR-side authenticated reverse
      # proxy that fronts exo on nodes 02/03. Consumed by the LiteLLM
      # proxy (`~/swarm/litellm_config.yaml`) as
      # `api_key: os.environ/GFR_EXO_AUTH_TOKEN` for the two GFR-exo
      # entries in the `coder` model group. Owned by `casazza` (not
      # `ingest`) because LiteLLM is launched under the login user from
      # `~/swarm/scripts/start-litellm.sh` for now — follow-up: promote
      # to a systemd unit with an EnvironmentFile pointing at
      # /run/secrets/gfr-exo-auth-token so the env-var plumbing stops
      # living in the wrapper script.
      #
      # Ciphertext ships with placeholder `REPLACE_ME_WITH_REAL_TOKEN`;
      # real value drops in via
      #   sops edit secrets/gfr-exo-auth-token.yaml
      # from a host holding the admin age key, once the GFR-side proxy
      # (see docs/design/gfr-exo-auth-proxy.md) is deployed.
      gfr-exo-auth-token = {
        sopsFile = ../../../secrets/gfr-exo-auth-token.yaml;
        key = "gfr_exo_auth_token";
        owner = "casazza";
        group = "users";
        mode = "0400";
      };

      # Grafana admin password. Consumed by local.observability via
      # `grafana.adminPasswordFile`, which the module wraps in a
      # `$__file{...}` reference inside services.grafana.settings so
      # the plaintext never lands in the Nix store. Owned by `grafana`
      # because Grafana (running as that user) reads the file directly
      # when expanding $__file{} on service start.
      grafana-admin-password = {
        sopsFile = ../../../secrets/grafana-admin-password.yaml;
        key = "grafana_admin_password";
        owner = "grafana";
        group = "grafana";
        mode = "0400";
      };

      # LiteLLM master key. Consumed by `local.litellm.masterKeyFile`
      # as a systemd `EnvironmentFile`, so the decrypted file's content
      # must be a single `KEY=VALUE` line. The sops YAML keeps the full
      # env-var line (`LITELLM_MASTER_KEY=sk-...`) under a single yaml
      # key; sops-nix extracts the VALUE of that key into the decrypted
      # file, which is exactly what systemd's env-file parser wants.
      # Owner is `litellm` so the LiteLLM unit can read it at start.
      litellm-master-key = {
        sopsFile = ../../../secrets/litellm-master-key.yaml;
        key = "litellm_master_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };

      # Per-client LiteLLM virtual keys. Each decrypts to a single
      # `LITELLM_API_KEY_<CLIENT>=sk-...` line which systemd loads as
      # an additive EnvironmentFile for the litellm unit (see
      # modules/nixos/litellm/default.nix, virtualKeys option).
      #
      # Placeholder values ship encrypted; actual keys are minted
      # post-rebuild via the LiteLLM `POST /key/generate` API
      # (authenticated with the master key) and written back through
      # `sops edit secrets/litellm-key-<client>.yaml`.
      #
      # Owner is `litellm` so the proxy's systemd unit can read the
      # decrypted files as an EnvironmentFile. Clients (claude-code,
      # opencode, hermes) read these indirectly — the wrapper shim
      # reads the sops-decrypted file at invocation time, so the
      # per-client owner is whoever invokes the client binary, not a
      # system user.
      litellm-key-claude-code-nixos = {
        sopsFile = ../../../secrets/litellm-key-claude-code-nixos.yaml;
        key = "litellm_api_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };
      litellm-key-claude-code-darwin = {
        sopsFile = ../../../secrets/litellm-key-claude-code-darwin.yaml;
        key = "litellm_api_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };
      litellm-key-opencode = {
        sopsFile = ../../../secrets/litellm-key-opencode.yaml;
        key = "litellm_api_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };
      litellm-key-opencode-darwin = {
        sopsFile = ../../../secrets/litellm-key-opencode-darwin.yaml;
        key = "litellm_api_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };
      litellm-key-hermes = {
        sopsFile = ../../../secrets/litellm-key-hermes.yaml;
        key = "litellm_api_key";
        owner = "litellm";
        group = "litellm";
        mode = "0400";
      };

      # LiteLLM OCI-mode secrets. Consumed by the litellm module when
      # `useOciContainer = true`. Both decrypt into dotenv-style
      # `KEY=VALUE` files that systemd/podman load directly via
      # `environmentFiles` / `EnvironmentFile`. Owner is `root`
      # because the render-env-file oneshot and the postgres+litellm
      # container units all run as root (podman backend).
      litellm-salt-key = {
        sopsFile = ../../../secrets/litellm-salt-key.yaml;
        key = "litellm_salt_key";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      litellm-pg-password = {
        sopsFile = ../../../secrets/litellm-pg-password.yaml;
        key = "litellm_pg_password";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Redis password for the seaweedfs instance (JuiceFS metadata KV).
      # Consumed by two units:
      #   1. redis-seaweedfs — loaded via `requirePassFile`; nixpkgs'
      #      redis module reads it into a temp config with `requirepass
      #      <file-contents>` at unit start (never enters /nix/store).
      #   2. juicefs-mount-shared — read via `$(cat …)` in the module's
      #      mount script and exported as META_PASSWORD so juicefs
      #      authenticates to redis.
      # Owner matches the redis-server per-instance user created by
      # `services.redis.servers.seaweedfs` (default: `redis-seaweedfs`).
      # juicefs-mount-shared runs as root so it can read regardless.
      redis-seaweedfs-password = {
        sopsFile = ../../../secrets/redis-seaweedfs-password.yaml;
        key = "redis_seaweedfs_password";
        owner = "redis-seaweedfs";
        group = "redis-seaweedfs";
        mode = "0400";
      };
    };
  };

  # ── ingestion pipeline ───────────────────────────────────────────────
  # Three pull-over-API source adapters (obsidian vault repo, Atlassian
  # Cloud, configurable GitHub repos) feeding one sink (Open WebUI
  # Knowledge API) through LangGraph graphs. Module at
  # modules/nixos/ingest/, project source under `projects/ingest/` in
  # this repo (same tree the langgraph-server unit pins below).
  #
  # Tokens/emails come from sops-nix (see `sops.secrets.*` above).
  # The ingest module reads each via its *File option; sops-nix puts
  # the decrypted plaintext at /run/secrets/<name> (root-owned, mode
  # 0400, group `ingest`).
  local.ingest = {
    enable = true;
    projectDir = ../../../projects/ingest;

    sinks.openwebui = {
      url = "http://localhost:8080";
      tokenFile = config.sops.secrets.openwebui-api-token.path;
      knowledges = {
        kb-it-tickets = "IT tickets pulled from Jira + GitHub issues";
        kb-it-docs = "IT runbooks, Confluence, and vault IT-Ops notes";
        kb-notes-personal = "Personal notes, journal, research from vault";
        kb-notes-meetings = "Meeting transcripts and action items";
        kb-systems-internal = "Internal system design/config/maintenance docs";
        kb-systems-external = "External vendor/upstream docs";
      };
    };

    sources = {
      obsidian = {
        type = "obsidian";
        enabled = true;
        schedule = "*:0/15"; # every 15 minutes
        repo = "ocasazza/obsidian";
        branch = "main";
        # Reuse the github PAT for private-repo clones. Open vaults can
        # drop this; keeping it wired makes the private case work without
        # re-encrypting a duplicate secret file.
        obsidianTokenFile = config.sops.secrets.github-api-token.path;
        # folderMap defaults match DEFAULT_OBSIDIAN_FOLDER_MAP in
        # ingest/config.py — no need to respecify here.
      };

      atlassian = {
        type = "atlassian";
        enabled = true;
        schedule = "*:0/30"; # every 30 minutes
        baseUrl = "https://schrodinger.atlassian.net";
        emailFile = config.sops.secrets.atlassian-email.path;
        tokenFile = config.sops.secrets.atlassian-api-token.path;
        # First-run scope: SYSMGR only (smaller of the two locked
        # Confluence targets) until the cme + langgraph rewrite lands.
        # Once Stage 8b is done, switch to confluenceTargets (URL list)
        # per the new module schema in
        # ~/.config/nixos-config/todo.md Stage 8c. Add itkb at that
        # point. See ~/Repositories/ocasazza/obsidian/todo.md Stage 8a.
        # Jira is similarly capped — turn on real projects when the
        # langgraph throttling work is done.
        jiraProjects = [ ];
        confluenceSpaces = [ "SYSMGR" ];
      };

      github = {
        type = "github";
        enabled = true;
        schedule = "*:0/30"; # every 30 minutes
        tokenFile = config.sops.secrets.github-api-token.path;
        repos = [
          {
            slug = "ocasazza/nixos-config";
            kind = "internal";
            includeIssues = false;
            includePRs = false;
            includeDocs = true;
          }
          {
            slug = "open-webui/open-webui";
            kind = "external";
            includeIssues = false;
            includePRs = false;
            includeDocs = true;
          }
        ];
      };
    };
  };

  # Local Claude Code on luna. Routes through the LiteLLM proxy above:
  #   * Default model pins to `coder-local` (luna's own vLLM) for fast
  #     always-on completions with no cloud round trip.
  #   * cloudPassthrough = true keeps `/vertex/*` reachable — explicit
  #     `claude --model coder-cloud-claude ...` still works, and the
  #     existing apiKeyHelper (gcloud id-token) keeps vertex-proxy
  #     authenticated for those calls.
  #
  # Telemetry is now disabled at the client layer — LiteLLM's OTEL
  # callbacks cover per-call tracing into Phoenix (richer + correctly
  # attributed to the routing layer), and the client OTel pipeline
  # would produce noisy duplicate spans.
  programs.claude-code = {
    enable = true;
    litellm = {
      enable = true;
      # loopback to avoid the LAN hop for luna's own claude-code
      endpoint = "http://localhost:4000";
      # In useVirtualKeys mode the bootstrap oneshot writes the minted
      # key to /run/litellm-oci/keys/<keyAlias>; the wrapper reads it
      # via `cut -d= -f2-` at every invocation. Falling back to the
      # sops path requires flipping useVirtualKeys = false (rollback).
      virtualKeyFile = "/run/litellm-oci/keys/claude-code-nixos";
      defaultGroup = "coder-local";
      cloudPassthrough = true;
      # Team membership — contributes to local.litellm.clientKeys via
      # the nixos claude-code module, so the bootstrap mints this key
      # under the dev team's ACL/budget.
      team = "dev";
      keyAlias = "claude-code-nixos";
    };
    telemetry.enable = false;
  };

  # ── opencode ─────────────────────────────────────────────────────────
  # opencode running on luna, routed exclusively through LiteLLM at
  # localhost:4000. Local-only — no anthropic/cloud passthrough is
  # exposed via `enabled_providers`, even though LiteLLM upstream supports
  # /vertex. The point of running opencode here at all is to drive the
  # archive ingestion + graphify pipelines (vault todo Stages 5-6) using
  # the local vLLM, free at the marginal call.
  #
  # The clientKeys.opencode entry below in `local.litellm` provisions the
  # key; the bootstrap oneshot mints it post-rebuild and writes
  # /run/litellm-oci/keys/opencode in dotenv shape
  # (`LITELLM_API_KEY_OPENCODE=sk-...`). The opencode wrapper sources
  # that file via `secrets.file`.
  programs.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.system}.default;
    telemetry = {
      enable = true;
      # Same otelcol that claude-code on the Macs feeds — see
      # modules/nixos/observability/. Spans land in Phoenix at :6006.
      endpoint = "http://localhost:4318";
    };
    managedConfig = {
      share = "disabled";
      # ONLY luna-litellm. No cloud, no exo (exo on the Macs is for
      # hermes; luna-side opencode goes through luna-litellm which can
      # itself federate to exo via the `coder-remote` model group).
      enabled_providers = [ "luna-litellm" ];
      provider.luna-litellm = {
        npm = "@ai-sdk/openai-compatible";
        name = "Luna LiteLLM";
        options = {
          baseURL = "http://localhost:4000/v1";
          # Read at runtime from the dotenv file sourced via secrets.file;
          # the {env:...} interpolation is opencode's standard shape.
          apiKey = "{env:LITELLM_API_KEY_OPENCODE}";
        };
        models = {
          # Mirror the model entries from the obsidian repo's
          # .opencode/opencode.json so user-level config and managed
          # config agree on names. Model IDs match LiteLLM model groups
          # declared in `local.litellm.modelGroups` below.
          coder-local = {
            name = "Luna coder (local vLLM, Qwen3-Coder-30B AWQ)";
            limit = {
              context = 32768;
              output = 8192;
            };
          };
          coder-remote = {
            name = "Coder remote (exo + GFR federation)";
            limit = {
              context = 262144;
              output = 8192;
            };
          };
          embedding = {
            name = "Qwen3-Embedding-0.6B";
            limit = {
              context = 2048;
              output = 0;
            };
          };
        };
      };
    };
    secrets.file = "/run/litellm-oci/keys/opencode";
  };

  # ── Phoenix (OTLP trace sink + UI) ──────────────────────────────────
  # Declarative systemd unit for Arize Phoenix. Completes the swarm
  # migration off `projects/swarm/scripts/*` — LiteLLM and LangGraph
  # Server were promoted earlier, Phoenix lives in
  # `modules/nixos/phoenix/` now. LangGraph Server + LiteLLM's default
  # `phoenixEndpoint` already points at `http://localhost:6006/v1/traces`,
  # so no extra wiring needed.
  #
  # Firewall opens :6006 (UI + OTLP/HTTP) and :4319 (OTLP/gRPC).
  local.phoenix = {
    enable = true;
    openFirewall = true;
  };

  # ── LiteLLM proxy ────────────────────────────────────────────────────
  # OpenAI-compatible federator in front of vLLM (:8000, :8002), local
  # exo (:52416), the GFR-exo federation, and (as a passthrough) the
  # Schrödinger vertex-proxy for Anthropic/GCP. Every AI client in the
  # fleet (claude-code nixos, claude-code darwin, opencode, hermes)
  # reaches their upstreams exclusively through this endpoint at :4000.
  #
  # Model groups are assembled here from the module's modelGroups option
  # (see `modules/nixos/litellm/default.nix`) — the YAML config is
  # rendered at build time, not hand-written. Adding a new backend is a
  # one-line edit in this file.
  #
  # Auth shape:
  #   * Master key  (`sops.secrets.litellm-master-key`) — used by
  #     internal LangGraph/swarm workers and by the user bootstrapping
  #     virtual keys via `POST /key/generate`.
  #   * Virtual keys (`sops.secrets.litellm-key-*`) — one per external
  #     client. Each surfaces as `LITELLM_API_KEY_<CLIENT>` in the
  #     proxy's env via an additive EnvironmentFile; placeholder values
  #     ship encrypted and are replaced post-bootstrap.
  #   * Cloud pass-through (`/vertex`) — LiteLLM forwards the client's
  #     Authorization header verbatim; no auth state on our side.
  local.litellm = {
    enable = true;
    endpoint = "http://luna:4000";
    openFirewall = true;
    masterKeyFile = config.sops.secrets.litellm-master-key.path;

    # OCI-container mode. Swaps the nix-native venv systemd unit for
    # `ghcr.io/berriai/litellm-database:main-stable` + a sidecar
    # Postgres container. The UI at /ui is broken on the venv path
    # because prisma-python has no `linux-nixos` Rust query-engine
    # build to fetch; the official image bundles both engines and runs
    # `prisma db push` at start.
    #
    # Salt key AES-encrypts DB-stored credentials — NEVER rotate once
    # seeded or the DB rows become undecryptable. Placeholder ships
    # encrypted; replace with `openssl rand -hex 32` via
    #   sops edit secrets/litellm-salt-key.yaml
    # (and the Postgres password similarly).
    useOciContainer = true;
    saltKeyFile = config.sops.secrets.litellm-salt-key.path;
    postgres.passwordFile = config.sops.secrets.litellm-pg-password.path;

    modelGroups = {
      # luna's vLLM coder — always-on anchor for plan/reduce/any
      # latency-sensitive step. Single deployment, weight 10.
      coder-local = [
        {
          models = [ "openai/cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ" ];
          api_base = "http://localhost:8000/v1";
          api_key = "sk-vllm-luna";
          weight = 10;
          max_tokens = 8192;
          timeout = 120;
        }
      ];

      # Fan-out pool: local exo (SSH tunnel to :52416) + GFR exo on
      # nodes 02/03 via the authenticated reverse proxy. Dark most of
      # the time; cooldown_time quarantine in routerSettings absorbs
      # offline nodes.
      coder-remote = [
        {
          models = [ "openai/qwen-3-coder-30b" ];
          api_base = "http://localhost:52416/v1";
          api_key = "sk-exo-local";
          weight = 1;
          max_tokens = 8192;
          timeout = 120;
        }
        {
          models = [ "openai/qwen-3-coder-30b" ];
          api_base = "https://gfr-proxy.schrodinger.com/exo/02/v1";
          api_key = "placeholder-not-yet-deployed";
          weight = 1;
          max_tokens = 8192;
          timeout = 120;
        }
        {
          models = [ "openai/qwen-3-coder-30b" ];
          api_base = "https://gfr-proxy.schrodinger.com/exo/03/v1";
          api_key = "placeholder-not-yet-deployed";
          weight = 1;
          max_tokens = 8192;
          timeout = 120;
        }
      ];

      # Cloud Claude via vertex-proxy. api_key = forwarded-per-request
      # means LiteLLM's client-construct step passes (a literal is
      # required by the SDK) but the client's actual Authorization
      # header is what reaches vertex-proxy via the /vertex passthrough
      # below — not this value. See modules/nixos/litellm for details.
      coder-cloud-claude = [
        {
          models = [ "anthropic/claude-opus-4-7" ];
          api_base = "https://vertex-proxy.sdgr.app/v1";
          api_key = "forwarded-per-request";
          weight = 1;
          max_tokens = 8192;
          timeout = 120;
        }
        {
          models = [ "anthropic/claude-sonnet-4-6" ];
          api_base = "https://vertex-proxy.sdgr.app/v1";
          api_key = "forwarded-per-request";
          weight = 1;
          max_tokens = 8192;
          timeout = 120;
        }
      ];

      # Qwen3-Embedding-0.6B on luna:8002 (FP16). Powers LocalGPT
      # semantic search in Obsidian, swarm MCP tools, Open WebUI
      # Knowledge RAG quality.
      embedding = [
        {
          models = [ "openai/Qwen/Qwen3-Embedding-0.6B" ];
          api_base = "http://localhost:8002/v1";
          api_key = "sk-vllm-luna";
          weight = 10;
          max_tokens = 8192;
          timeout = 60;
        }
      ];
    };

    # /vertex/* → vertex-proxy. Clients keep their apiKeyHelper
    # (gcloud id-token); LiteLLM forwards the bearer untouched.
    passthroughEndpoints.vertex = {
      path = "/vertex";
      target = "https://vertex-proxy.sdgr.app";
      forwardHeaders = true;
    };

    # Router-level model name aliases. Lets clients reference Anthropic
    # upstream model ids directly (the ones models.dev publishes and
    # claude-code defaults to) without us having to duplicate model_list
    # rows. All aliased names land in the `coder-cloud-claude` group,
    # which routes to vertex-proxy and is gated by the dev team
    # allowlist on top.
    #
    # Add a new upstream model id by appending one line here — no team
    # or virtual-key change needed.
    routerSettings.modelGroupAlias = {
      "claude-opus-4-7" = "coder-cloud-claude";
      "claude-opus-4-6" = "coder-cloud-claude";
      "claude-opus-4-5" = "coder-cloud-claude";
      "claude-sonnet-4-7" = "coder-cloud-claude";
      "claude-sonnet-4-6" = "coder-cloud-claude";
      "claude-sonnet-4-5" = "coder-cloud-claude";
      "claude-haiku-4-5" = "coder-cloud-claude";
    };

    # Per-client virtual keys: each sops-decrypted EnvironmentFile is
    # added to the proxy's env when the legacy venv path is in use.
    # In OCI+useVirtualKeys mode the bootstrap oneshot writes minted
    # values to /run/litellm-oci/keys/<client> instead and this option
    # is unused — kept populated so a `useOciContainer = false`
    # rollback still finds the sops paths.
    virtualKeys = {
      claude-code-nixos = config.sops.secrets.litellm-key-claude-code-nixos.path;
      claude-code-darwin = config.sops.secrets.litellm-key-claude-code-darwin.path;
      opencode = config.sops.secrets.litellm-key-opencode.path;
      opencode-darwin = config.sops.secrets.litellm-key-opencode-darwin.path;
      hermes = config.sops.secrets.litellm-key-hermes.path;
    };

    # ── Declarative team + virtual-key provisioning ─────────────────
    # The `litellm-team-bootstrap.service` oneshot reconciles these
    # against LiteLLM's admin API on every rebuild. See
    # `~/.claude/plans/litellm-teams.md` for the full design. Minted
    # key values land in /run/litellm-oci/keys/<client>; darwin hosts
    # pick up the same values via sops-nix after the operator copies
    # them into `secrets/litellm-key-<client>.yaml` via `sops edit`
    # (writeback automation is a follow-up, §1g of the plan).
    useVirtualKeys = true;

    teams = {
      dev = {
        description = "Interactive-dev: claude-code (both) + opencode";
        # Allowlist gates the raw `model:` value the client sends, BEFORE
        # router_settings.model_group_alias rewrites it. So even though
        # `claude-opus-4-7` aliases to `coder-cloud-claude` at routing
        # time, the team ACL would still reject the request unless the
        # alias name is in this list. Keep these in sync with the
        # `routerSettings.modelGroupAlias` map below — every alias key
        # needs an entry here.
        models = [
          "coder-local"
          "coder-remote"
          "coder-cloud-claude"
          "embedding"
          # Anthropic upstream model ids opencode picks from models.dev
          # and that claude-code might default to. Each routes back to
          # `coder-cloud-claude` via modelGroupAlias.
          "claude-opus-4-7"
          "claude-opus-4-6"
          "claude-opus-4-5"
          "claude-sonnet-4-7"
          "claude-sonnet-4-6"
          "claude-sonnet-4-5"
          "claude-haiku-4-5"
        ];
        tpm = 400000;
        rpm = 1200;
        maxBudget = 50.0;
        budgetDuration = "30d";
      };

      prod = {
        description = "Always-on agents: hermes";
        models = [
          "coder-local"
          "embedding"
        ];
        tpm = 60000;
        rpm = 120;
        maxBudget = 10.0;
        budgetDuration = "30d";
      };
    };

    # Client-key declarations on luna. The local claude-code nixos
    # module contributes `claude-code-nixos` automatically via its
    # `litellm.team` option; the other three (darwin claude-code,
    # opencode, hermes) live in separate host/module configs that
    # don't run on luna, so their entries are declared explicitly here
    # so the bootstrap mints their keys.
    clientKeys = {
      claude-code-darwin = {
        team = "dev";
        keyAlias = "claude-code-darwin";
        # Darwin hosts need the value in sops so sops-nix can surface
        # it at /run/secrets on the Mac. Writeback unit TBD (plan
        # §1g); until it lands, the operator manually copies the
        # minted value from /run/litellm-oci/keys/claude-code-darwin
        # on luna into the sops yaml via `sops edit`.
        sopsFile = ../../../secrets/litellm-key-claude-code-darwin.yaml;
      };
      opencode = {
        team = "dev";
        keyAlias = "opencode";
        sopsFile = ../../../secrets/litellm-key-opencode.yaml;
      };
      opencode-darwin = {
        team = "dev";
        keyAlias = "opencode-darwin";
        # Per-system opencode key. Mirrors the claude-code-nixos /
        # claude-code-darwin split: each platform-specific opencode
        # client gets an independently-revocable key. Real value was
        # minted ad-hoc against the LiteLLM admin API and committed
        # to secrets/litellm-key-opencode-darwin.yaml; bootstrap will
        # see it on /run/litellm-oci/keys/opencode-darwin and skip
        # re-minting on future rebuilds.
        sopsFile = ../../../secrets/litellm-key-opencode-darwin.yaml;
      };
      hermes = {
        team = "prod";
        keyAlias = "hermes";
        sopsFile = ../../../secrets/litellm-key-hermes.yaml;
      };
    };
  };

  # ── LangGraph Server (dev mode, in-memory SQLite) ───────────────────
  # One `langgraph dev` per project, each pinned to its own venv under
  # /var/lib/langgraph/venv/<name>. Graphs are defined by the project's
  # own langgraph.json + pyproject.toml; the module just plumbs OTEL
  # into Phoenix and OPENAI_API_BASE into the LiteLLM proxy.
  #
  # `databaseUrl = null` → in-memory SQLite checkpointer. Runs evaporate
  # on restart — acceptable for dev, not for anything you want durable.
  # Flip to a real Postgres URL (and add `services.postgresql` below)
  # when you want runs to survive reboots.
  #
  # Security: :2024 only opens the LAN firewall for the swarm project
  # because that's the one you actually point Studio at. ingest is
  # internal-only (pull-sync oneshots fire via timer, no UI), so leave
  # it loopback-local.
  #
  # Project sources live under `projects/<name>/` in this repo and are
  # referenced here as relative nix paths. At build time Nix hashes the
  # tree into `/nix/store/<hash>-<name>/`; the systemd unit's venv
  # bootstrap runs `uv pip install --editable` against that store path,
  # so every rebuild picks up pyproject / uv.lock bumps atomically.
  # Add a project: drop it under `projects/<name>/` with a
  # `langgraph.json` + `pyproject.toml`, then add an entry below.
  local.langgraphServer = {
    enable = true;
    projects = {
      swarm = {
        projectDir = ../../../projects/swarm;
        port = 2024;
        openFirewall = true;
      };
      ingest = {
        projectDir = ../../../projects/ingest;
        port = 2025;
        openFirewall = false;
      };
    };
  };

  # ── LangGraph OCI (free self-hosted production stack) ───────────────
  # Parallel-track with `local.langgraphServer` above. Runs the
  # `langchain/langgraph-api` image in two roles (API + worker) against
  # a dedicated Postgres + loopback Redis on :6380, so scheduled runs
  # survive restarts (the `langgraph dev` path above loses them).
  #
  # LEFT COMMENTED OUT on purpose — flip over in a dedicated PR once
  # the image + Postgres + Redis topology has been validated:
  #   1. (optional) pin the image to a specific tag for reproducibility,
  #      e.g. `image = "docker.io/langchain/langgraph-api:0.2.75";`
  #   2. drop the `local.langgraphServer.enable = true` block above
  #      (or set to false on each project) so ports :2024/:2025 free up,
  #      then (optionally) move `port = 2026/2027` defaults below to
  #      :2024/:2025 for drop-in client compatibility.
  #   3. add the sops secret stanza for `langgraph-pg-password` (see
  #      `sops.secrets` block below) so the Postgres role password can
  #      be decrypted at activation.
  #   4. `sudo nixos-rebuild switch`.
  #   5. curl http://luna.local:2026/ok (swarm), :2027/ok (ingest).
  #
  # local.langgraphOci = {
  #   enable = true;
  #   # Pin in production — `:latest` is updated frequently and can
  #   # silently change the API surface on a pull-on-restart.
  #   # image = "docker.io/langchain/langgraph-api:0.2.75";
  #   postgres.passwordFile = config.sops.secrets.langgraph-pg-password.path;
  #   projects = {
  #     swarm = {
  #       projectDir = ../../../projects/swarm;
  #       port = 2026;
  #       openFirewall = true;
  #       env = {
  #         OPENAI_API_BASE = "http://127.0.0.1:4000/v1";
  #         OPENAI_API_KEY  = "sk-swarm-local";
  #         OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:6006/v1/traces";
  #         PHOENIX_COLLECTOR_ENDPOINT  = "http://127.0.0.1:6006/v1/traces";
  #         OTEL_SERVICE_NAME           = "langgraph-swarm";
  #       };
  #     };
  #     ingest = {
  #       projectDir = ../../../projects/ingest;
  #       port = 2027;
  #       openFirewall = false;
  #       env = {
  #         OPENAI_API_BASE = "http://127.0.0.1:4000/v1";
  #         OPENAI_API_KEY  = "sk-swarm-local";
  #         OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:6006/v1/traces";
  #         PHOENIX_COLLECTOR_ENDPOINT  = "http://127.0.0.1:6006/v1/traces";
  #         OTEL_SERVICE_NAME           = "langgraph-ingest";
  #       };
  #     };
  #   };
  # };
  #
  # Paired sops secret stanza (add into `sops.secrets` below when
  # enabling the OCI stack):
  # sops.secrets.langgraph-pg-password = {
  #   sopsFile = ../../../secrets/langgraph-pg-password.yaml;
  #   key = "langgraph_pg_password";
  #   owner = "root";
  #   group = "root";
  #   mode = "0400";
  # };

  # ── shared storage stack (SeaweedFS + Redis + JuiceFS) ──────────────
  # luna is the single source of truth for the personal cluster's
  # filesystem. It runs:
  #   * seaweedfs master + volume + filer + S3 gateway (object store)
  #   * redis (JuiceFS metadata KV — single-instance, loopback-only)
  #   * juicefs mount on /mnt/juicefs (POSIX layer over the above)
  #
  # Redis replaced TiKV as the JuiceFS metadata backend. TiKV 8.5.0's
  # vendored C++ tree (grpcio-sys → rocksdb-sys → abseil lts_20211102)
  # does not build under the current gcc 15 / cmake 4.1 stdenv, and
  # none of the fixes land cleanly without patching abseil in-tree.
  # Redis is a first-class JuiceFS metadata backend (`redis://` URL
  # scheme, `META_PASSWORD` env for auth) and the user opted for
  # "Redis everywhere" across the personal cluster.
  #
  # Macs in the fleet only run the JuiceFS *client* against luna's PD
  # and S3. See systems/aarch64-darwin/<host>/default.nix — their
  # metaUrl needs the same migration in a follow-up; for now they
  # point at TiKV and will fail to mount until updated.
  #
  # Secret seeding (one-time, out-of-band — sops-nix is not wired into
  # nixos-config yet; secret files are managed manually until then):
  #   sudo install -d -m 0700 -o seaweedfs -g seaweedfs /var/lib/seaweedfs
  #   sudo install -m 0600 -o seaweedfs -g seaweedfs \
  #     <(openssl rand -hex 32) /var/lib/seaweedfs/admin-secret
  #   sudo install -d -m 0700 -o root -g root /var/lib/juicefs-secrets
  #   echo -n 'admin' | sudo install -m 0600 /dev/stdin /var/lib/juicefs-secrets/access-key
  #   sudo cp /var/lib/seaweedfs/admin-secret /var/lib/juicefs-secrets/secret-key
  #   sudo chmod 0600 /var/lib/juicefs-secrets/*
  services.seaweedfs = {
    enable = true;
    bindIP = "0.0.0.0"; # LAN-only; tighten when Tailscale is in place
    cluster = {
      # Single-host deployment: peer entry must STRING-MATCH the
      # self-bind (`-ip:-port` = `0.0.0.0:9333`) so SeaweedFS' peer
      # dedup collapses them to 1 (odd, satisfies Raft quorum).
      # Past attempts and why they failed:
      #   * `[ "luna.local:9333" ]` — string ≠ `0.0.0.0:9333`, counted
      #     as 2 peers, master fatal-exited.
      #   * `[ ]` — master ok, but filer requires ≥1 master peer.
      #   * `[ "localhost:9333" ]` — also string ≠ `0.0.0.0:9333`,
      #     same 2-peer crash (commit 21fb208 mistakenly believed it
      #     deduped).
      # `[ "0.0.0.0:9333" ]` matches the bind literal, dedupes to 1.
      # Scale to an odd N ≥ 3 (with real hostnames) when federating.
      masterPeers = [ "0.0.0.0:9333" ];
      dataCenter = "home";
      rack = "luna";
    };
    master = {
      enable = true;
      defaultReplication = "000"; # single-host cluster — no redundancy
    };
    volume = {
      enable = true;
      maxVolumes = 100; # ~3 TB at 30 GB/volume; well within luna's free space
      port = 8081; # default 8080 collides with Open WebUI
      # metricsPort defaults to 8081 in the seaweedfs module — collides
      # with the volume server's main port. Bump to 8082 (free) so
      # both can bind. Without this, seaweedfs-volume crash-loops with
      # `bind: address already in use` even though no other process
      # has the port (the volume server's own metricsPort grabbed it
      # first within the same process and the volume listener fails).
      metricsPort = 8082;
    };
    filer = {
      enable = true;
      mount.enable = false; # JuiceFS handles the POSIX mount, not weed
      # otelcol-contrib's internal-metrics listener was moved off
      # 127.0.0.1:8888 → 127.0.0.1:8893 in modules/nixos/observability
      # specifically so seaweedfs-filer can keep its standard port
      # (and its computed gRPC port 18888, which `weed s3 -filer=…` and
      # any future `weed mount` clients hardcode by deriving from the
      # http port).
      metricsPort = 8890; # default 8889 collides with OTel collector Prom bridge
    };
    s3 = {
      enable = true;
      accessKey = "admin";
      secretKeyFile = "/var/lib/seaweedfs/admin-secret";
    };
    openFirewall = true;
  };

  # The seaweedfs nixos module's s3 unit exports `AWS_ACCESS_KEY_ID=admin`
  # but intentionally skips `AWS_SECRET_ACCESS_KEY` (a comment in the
  # module's start script says gfr handles this via a "separate
  # mechanism"). Without the secret in env, the S3 server has no
  # credentials registered and every call returns InvalidAccessKeyId.
  # We splice the secret in here as a runtime env-file rendered from
  # /var/lib/seaweedfs/admin-secret (root-owned, mode 0600), matching
  # the litellm OCI db-url pattern: render-then-include, never bake
  # plaintext into /nix/store.
  systemd.services."seaweedfs-s3" = {
    serviceConfig.EnvironmentFile = "/run/seaweedfs-s3-env";
  };
  systemd.services."seaweedfs-s3-env" = {
    description = "Render runtime EnvironmentFile (AWS_SECRET_ACCESS_KEY) for seaweedfs-s3";
    wantedBy = [ "multi-user.target" ];
    before = [ "seaweedfs-s3.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    script = ''
      umask 077
      install -m 0600 -o root -g root /dev/null /run/seaweedfs-s3-env
      printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(cat /var/lib/seaweedfs/admin-secret)" \
        > /run/seaweedfs-s3-env
    '';
  };

  # Redis — JuiceFS metadata KV. LAN-exposed so Macs can mount JuiceFS
  # with metaUrl=redis://luna.local:6379/0. Auth via requirePassFile is
  # the only thing standing between any LAN host and the metadata KV;
  # the password (sops-managed) is re-encrypted to every host_*  age
  # key in `.sops.yaml` so each Mac surfaces it at activation. RDB
  # snapshotting is on by default so a luna reboot doesn't lose the
  # metadata index.
  services.redis.servers.seaweedfs = {
    enable = true;
    # WAS bind = "127.0.0.1"; flipped to 0.0.0.0 for the JuiceFS-on-
    # all-Macs rollout — see todo.md Stage 0.9.
    bind = "0.0.0.0";
    port = 6379;
    # Auth required even on loopback — matches "Redis everywhere"
    # direction where any future federation (Tailscale, WireGuard,
    # etc.) already has credentials in place.
    requirePassFile = config.sops.secrets.redis-seaweedfs-password.path;
  };
  # `services.redis.servers.<name>` doesn't have an `openFirewall`
  # option; open :6379 manually so Macs in the fleet can reach it.
  networking.firewall.allowedTCPPorts = [ 6379 ];

  # TiKV via OCI container (parallel-track, not in the hot JuiceFS path).
  # JuiceFS metadata lives in Redis above; this runs pingcap/pd +
  # pingcap/tikv from their upstream OCI images so we keep a working
  # TiKV cluster around for eval / future apps without fighting the
  # source-build breakage on the nixpkgs tikv derivation (TiKV 8.5.0's
  # vendored rocksdb-sys / grpcio-sys C++ tree doesn't build under the
  # current gcc 15 / cmake 4.1 stdenv). PD publishes on 127.0.0.1:2379
  # and TiKV on 127.0.0.1:20160 by default — loopback-only, because
  # the module doesn't ship TLS+auth. Don't flip openFirewall without
  # wiring those in first.
  local.tikvOci = {
    enable = true;
    # openFirewall left at default (false) — parallel-track eval install.
  };

  services.juicefs = {
    enable = true;
    mounts.shared = {
      # Password is injected as META_PASSWORD at unit-start by the
      # juicefs module, so the URL stays credential-free.
      metaUrl = "redis://127.0.0.1:6379/0";
      metaPasswordFile = config.sops.secrets.redis-seaweedfs-password.path;
      storageType = "s3";
      bucket = "http://luna.local:8333/shared";
      mountPoint = "/mnt/juicefs";
      accessKeyFile = "/var/lib/juicefs-secrets/access-key";
      secretKeyFile = "/var/lib/juicefs-secrets/secret-key";
      formatOnFirstBoot = true;
      cacheDir = "/var/cache/juicefs/shared";
      cacheSize = 10240; # 10 GiB local read cache
    };
  };

  # ── git-daemon: read-only LAN git transport for flake inputs ────
  # Bare repos at /srv/git/<name>.git served at git://luna.local/<name>
  # on port 9418. Pushes go via ssh (casazza@luna.local:/srv/git/...).
  # See modules/nixos/git-daemon/ for the module + nixos-config/todo.md
  # Stage 0 for why this exists.
  #
  # Bootstrap (one-time, out-of-band — module never auto-creates repos):
  #   sudo install -d -m 0755 -o git-daemon -g git-daemon /srv/git
  #   sudo -u git-daemon git clone --bare \
  #     /home/casazza/Repositories/schrodinger/opencode \
  #     /srv/git/opencode.git
  #   # ditto for hermes-agent and obsidian
  local.gitDaemon = {
    enable = true;
    openFirewall = true; # LAN-only; tighten if luna gains untrusted IFs
    repos = [
      "opencode"
      "hermes-agent"
      "obsidian"
    ];
  };

  # luna shipped as NixOS 25.11 by the original installer; honor the
  # original stateVersion so per-user data files keep their existing
  # schema (the value should never change post-install per nixpkgs docs).
  system.stateVersion = "25.11";
}
