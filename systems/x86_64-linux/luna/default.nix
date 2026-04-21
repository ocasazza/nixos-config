{
  pkgs,
  lib,
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
# IMPORTANT: luna was bootstrapped with a stock NixOS installer (not
# disko) by an earlier `olive` user. We:
#   1. Preserve the existing partition layout (no disko import) by
#      mirroring /etc/nixos/hardware-configuration.nix here.
#   2. Migrate `olive` -> `casazza` (the canonical user across this
#      flake) via a one-shot system activation script that renames
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
    # disko spec: snapshot of luna's existing partitions on nvme1n1
    # (system) + nvme0n1 (scratch btrfs) + sda/sdb (mdadm RAID1).
    # See modules/nixos/disk-config.nix for layout details.
    ../../../modules/nixos/disk-config.nix
    ../../../modules/shared
    ../../../modules/shared/cachix
  ];

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

      # initialPassword fires only on first user creation. Set so we
      # have a way in if SSH keys ever break — change with `passwd`
      # after first login.
      initialPassword = "changeme";
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
        # AWQ is small enough that we can be more aggressive on util —
        # most of the budget goes to KV cache.
        gpuMemoryUtilization = 0.85;
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
    };
  };

  # ── open-webui ───────────────────────────────────────────────────────
  # Browser-based chat frontend for the local vLLM endpoint(s). Backend
  # URLs auto-derive from `local.vllm.services` above, so adding an
  # embedding/chat service later wires it into the UI on next switch.
  #
  # First boot:
  #   1. nixos-rebuild switch
  #   2. open http://luna.local:8080  → first signup becomes admin
  #   3. set `local.openWebUI.signupEnabled = false;` and rebuild to
  #      seal the instance
  local.openWebUI = {
    enable = true;
    openFirewall = true;
  };

  # ── observability ────────────────────────────────────────────────────
  # Local Prometheus + Grafana + node/GPU/vLLM scrapes. Module lives in
  # `modules/nixos/observability/`. Auto-discovers vllm services from
  # `local.vllm.services` so adding an embedding endpoint later wires
  # itself into the dashboard.
  #
  # After first deploy:
  #   * Grafana UI → http://luna.local:3000  (admin / changeme)
  #   * Import dashboards by ID: 1860 (node), 14574 (NVIDIA GPU)
  #   * vLLM panels: build from /metrics — no canonical dashboard yet.
  local.observability = {
    enable = true;
    openFirewall = true;
    grafana.adminPassword = "changeme"; # set via UI on first login
  };

  # Event-driven obsidian repo pull. Triggered remotely by the editing
  # Mac via `claw -w @vault-consumers systemctl start
  # obsidian-vault-sync.service` from a post-commit hook in the
  # obsidian repo. The repo must already be `jj git clone`'d to
  # /home/casazza/obsidian on first install (one-time bootstrap).
  local.obsidianVaultSync.enable = true;

  # Local Claude Code on luna. Telemetry endpoint is auto-derived by the
  # claude-code module — because `local.observability.enable = true` above,
  # the default flips to `http://127.0.0.1:4317` instead of luna.local, so
  # luna pushes to itself over loopback without an explicit override here.
  programs.claude-code.enable = true;

  # luna shipped as NixOS 25.11 by the original installer; honor the
  # original stateVersion so per-user data files keep their existing
  # schema (the value should never change post-install per nixpkgs docs).
  system.stateVersion = "25.11";
}
