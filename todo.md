# todo.md — infra side

Cross-agent coordination doc. Companion file:
`~/Repositories/ocasazza/obsidian/todo.md` (vault side). Both must stay in
sync; if you change one, glance at the other.

**Last updated:** 2026-04-22
**Owner:** opencode session, on Mac, working against luna over ssh

## Mac JuiceFS — blocked on reboot

**Status:** kext approved by MDM, AuxKC not rebuilt → kext won't load →
launchd job for `org.juicefs.mount-shared` is forced `Disabled = true`
on `GN9CFLM92K-MBP` (see commit `73fe611b`,
`systems/aarch64-darwin/GN9CFLM92K-MBP/default.nix`). No mount, no
notification spam, but no Mac-side juicefs access either.

### What's already done

- macFUSE 5.2.0 installed at `/Library/Filesystems/macfuse.fs/` (legacy
  `.kext`, bundle id `io.macfuse.filesystems.macfuse.25` on the SDK-26
  build for macOS 26.3 / build 25D125).
- MDM configuration profile `net.casazza.macfuse-kext-allowlist`
  (payload `com.apple.syspolicy.kernel-extension-policy`,
  `AllowedTeamIdentifiers = ["3T5GSNBU6W"]`) pushed via Fleet
  (`fleetdm.sdgr.io`), declaratively sourced from
  `profiles/macfuse-kext-allowlist.mobileconfig`.
- Profile confirmed installed on **3 of 4 Macs**: `CK2Q9LN7PM-MBA`,
  `GJHC5VVN49-MBP`, `GN9CFLM92K-MBP`. `installedByMDM: TRUE` on this
  Mac (`GN9CFLM92K-MBP`) per `sudo profiles -P`.
- Launchd override committed (`73fe611b`) so the mount daemon doesn't
  thrash trying to load an unapproved kext.

### Why it's still blocked

`sudo kmutil load -p /Library/Filesystems/macfuse.fs/Contents/Extensions/26/macfuse.kext`
returns **"not approved to load."** On Apple Silicon, even an
allowlisted kext can't load until the **Auxiliary Kernel Collection
(AuxKC)** has been rebuilt to include it. The kernel only consumes a
new AuxKC at boot, so this is a one-time-per-Mac wait.

### Two paths to unblock — and why only one is real

**(a) Reboot.** At boot, the kernel rebuilds AuxKC using the now-
approved policy. No KDK needed. Per-Mac one-time. **User stated
preference is "no restart" → on hold.** This is the path we'll
eventually take; it costs nothing extra.

**(b) Install the KDK + run `kmutil create --new aux`.** Get the
Kernel Debug Kit for build `25D125` from
<https://developer.apple.com/download/all/?q=Kernel%20Debug%20Kit>
(free with Apple ID), then:

```sh
sudo kmutil create --new aux \
  -B /System/Library/KernelCollections/AuxiliaryKernelExtensions.kc \
  --bundle-path /Library/Filesystems/macfuse.fs/Contents/Extensions/26/macfuse.kext
```

`kmutil` only **stages** the new AuxKC; the kernel still only swaps it
in **at next boot**. So path (b) is **strictly worse** — it adds a KDK
download, a manual command, and **still requires a reboot**. Don't
relitigate this.

### Verification recipe (post-reboot)

```sh
sudo kmutil load -p /Library/Filesystems/macfuse.fs/Contents/Extensions/26/macfuse.kext  # exit 0
kmutil showloaded | grep -i fuse                                                          # macfuse listed
```

Then flip the launchd override off, either by editing nix:

```sh
# Remove the launchd.daemons.juicefs-mount-shared.serviceConfig
# block in systems/aarch64-darwin/GN9CFLM92K-MBP/default.nix
# (added in commit 73fe611b), then darwin-rebuild switch.
```

…or, more pragmatically for an immediate test before the rebuild:

```sh
sudo launchctl bootstrap system /Library/LaunchDaemons/org.juicefs.mount-shared.plist
```

Mount should land at `/Volumes/juicefs-shared` (per
`hosts/darwin/default.nix` `services.juicefs.mounts.shared`).

### Acceptance criteria — pre-reboot

- [ ] All four Macs show the profile installed (run on each):
  ```sh
  sudo profiles -P 2>&1 | grep "casazza.macfuse"
  ```
  Should print `_computerlevel[N] attribute: profileIdentifier:
  net.casazza.macfuse-kext-allowlist` on every host. Currently
  confirmed on 3/4: `CK2Q9LN7PM-MBA`, `GJHC5VVN49-MBP`,
  `GN9CFLM92K-MBP`. **`L75T4YHXV7-MBA` not yet verified** — was not
  in the user's "applied" list. Either:
    - Fleet didn't tag it for the same group → check team membership in
      `fleetdm.sdgr.io`.
    - Mac is offline / hasn't checked in → wake it and re-run.
  The host *is* declared in nix (`systems/aarch64-darwin/L75T4YHXV7-MBA/`),
  so this is purely an MDM operational gap, not a config drift.

### Workaround / parallel path: NFS export from luna

If reboots stay deferred and we still need cluster-shared FS on Macs
**now**, the kext-free option is to export `/mnt/juicefs` from luna
via NFS and mount it on each Mac with the macOS built-in NFS client
(no kext, no profile, no AuxKC). luna-side juicefs mount at
`/mnt/juicefs` already works (verified: writes/reads succeed).

Sketch (do NOT implement yet — separate todo item, evaluate after
Stage 1a lands):

```nix
# luna systems file, x86_64-linux/luna/default.nix
services.nfs.server = {
  enable = true;
  exports = ''
    /mnt/juicefs 192.168.0.0/16(rw,sync,no_subtree_check,fsid=1,insecure)
  '';
};
networking.firewall.allowedTCPPorts = [ 2049 111 ];
networking.firewall.allowedUDPPorts = [ 2049 111 ];
```

Mac mount via `services.juicefs.mounts.shared` would be replaced by a
plain `launchd.daemons.nfs-juicefs` running
`mount_nfs -o nolocks,resvport luna.local:/mnt/juicefs /Volumes/juicefs-shared`.
Trade: extra hop (Mac → NFS → luna → JuiceFS → SeaweedFS) vs. direct
(Mac → JuiceFS-FUSE → SeaweedFS), but no kext approval ever needed.

## Cross-cutting notes

- The `claude/seaweedfs-macs` branch carries the macFUSE override
  (`73fe611b`) plus the unrelated git-daemon / sops-nix / observability
  work in `bef53abf`. Once both are merged the mac override stays in
  the system flake until a deliberate post-reboot cleanup commit
  removes it.
- See vault-side `~/Repositories/ocasazza/obsidian/todo.md` for the
  bigger picture: the unblocked Mac JuiceFS mount is on the critical
  path for the Confluence-archive ingest only inasmuch as `luna:~/archive/`
  needs to be reachable from wherever opencode runs. Stage 1a
  (opencode-on-luna) sidesteps this entirely — opencode-on-luna reads
  the archive **directly** from luna's local filesystem, not via Mac
  JuiceFS. So this section is genuinely independent of the main
  ingest effort and can stay parked until a reboot is convenient.
