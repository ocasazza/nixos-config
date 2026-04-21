# disko layout for luna.
#
# Source of truth for luna's partition layout. We `disko-install` this
# from the live USB, which:
#   * wipes nvme1n1 (boot disk) and lays it out per the spec below
#   * preserves nvme0n1 (sk hynix scratch btrfs) — same UUID, no wipe
#     because disko diffs partlabels and is a no-op when they match
#   * leaves sda/sdb (SATA pair with stale mdadm superblocks) alone
#     entirely (not declared here, see comment further down)
#
# Layout:
#   nvme1n1 (WD_BLACK SN8100 2TB)  → boot/system disk
#     p1  vfat  1G    /boot   (ESP)         partlabel=EFI
#     p2  ext4  ~1.99T /      (root)         partlabel=root, label=root
#     p3  swap  8.8G  [SWAP]                partlabel=swap, label=swap
#
#   nvme0n1 (SK hynix 2TB)         → scratch btrfs at /mnt/scratch
#     p1  btrfs 100%                         partlabel=disk-nvme1-scratch
#     UUID 3cfb7055-1f72-4880-b40d-15ac4fda7bf2 (preserved across reformats)
#
# After `disko-install` the system mounts everything via
# `/dev/disk/by-partlabel/<label>` so reordering disks (sda/sdb swap)
# never breaks boot.
#
# Usage from live USB:
#   sudo nix --extra-experimental-features 'nix-command flakes' run \
#     github:nix-community/disko -- \
#     --mode disko \
#     --flake /mnt/etc/nixos#luna \
#     --override-input opencode          path:./modules/_stubs/empty \
#     --override-input hermes            path:./modules/_stubs/empty \
#     --override-input git-fleet         path:./modules/_stubs/empty \
#     --override-input git-fleet-runner  path:./modules/_stubs/empty
#
# (Or `disko-install --flake .#luna --disk nvme1n1 /dev/nvme1n1` if
# you want disko to also run nixos-install in one shot.)
_:

let
  # Stable UUIDs preserved across re-installs so any external scripts
  # mounting by-uuid stay valid.
  rootUuid = "83808180-0f20-4b30-ab7a-ae058ff4a28b";
  swapUuid = "55f8b15e-1197-46d5-9e75-9ff28214fd43";
  scratchUuid = "3cfb7055-1f72-4880-b40d-15ac4fda7bf2";
in
{
  disko.devices = {
    disk = {
      # ── boot / system disk ─────────────────────────────────────────
      nvme1n1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          # Partition order matters for disko: fixed-size first,
          # `100%` last — disko fills `100%` with the remainder.
          partitions = {
            EFI = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            swap = {
              # 9G ≈ the 8.8G that was there before. disko's size
              # pattern doesn't accept decimals.
              size = "9G";
              content = {
                type = "swap";
                resumeDevice = false;
                extraArgs = [
                  "-L"
                  "swap"
                  "-U"
                  swapUuid
                ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [
                  "-L"
                  "root"
                  "-U"
                  rootUuid
                ];
              };
            };
          };
        };
      };

      # ── scratch (btrfs single, no subvolumes) ──────────────────────
      nvme0n1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions.disk-nvme1-scratch = {
            size = "100%";
            content = {
              type = "btrfs";
              # Pre-existing single-volume btrfs. We don't define
              # subvolumes so disko leaves them alone on no-op runs.
              extraArgs = [
                "-L"
                "scratch"
                "-U"
                scratchUuid
              ];
              mountpoint = "/mnt/scratch";
              mountOptions = [
                "compress=zstd"
                "noatime"
                "nofail" # don't block boot if the disk is missing
              ];
            };
          };
        };
      };

      # ── 2× WD 1TB SATA: NOT managed by disko ───────────────────────
      # luna has 2 SATA disks (sda, sdb) with leftover mdadm
      # superblocks for an `any:storage_array` RAID1 from a previous
      # install. The array is NOT currently assembled.
      #
      # We deliberately leave them out of disko because including
      # them with `mdraid` content would force `boot.swraid.enable`,
      # and an unassembled array tips boot into emergency mode (even
      # with `nofail` set on the mount, systemd waits forever for
      # `/dev/md/storage_array` to appear).
      #
      # If you want to bring the array back online later:
      #   1. SSH to luna
      #   2. `sudo mdadm --assemble --scan`
      #   3. `sudo mkdir -p /mnt/storage`
      #   4. `sudo mount /dev/md/storage_array /mnt/storage`
      #   5. Once stable, declare sda/sdb + mdadm.storage_array here
      #      with the right superblock UUID and re-deploy
    };
  };

  # `boot.swraid.enable` defaults to false; with no mdadm entries
  # above, disko doesn't force it on, and systemd doesn't wait for
  # any /dev/md* devices at boot.
}
