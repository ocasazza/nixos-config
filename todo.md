# todo.md — infra side

Cross-agent coordination doc. Companion file:
`~/Repositories/ocasazza/obsidian/todo.md` (vault side). Both must stay in
sync; if you change one, glance at the other.

**Last updated:** 2026-04-23 (Stage 8 retargeted: cme + langgraph-as-throttle for itkb/SYSMGR)
**Owner:** opencode session, on Mac, working against desk-nxst-001 over ssh

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
    The host _is_ declared in nix (`systems/aarch64-darwin/L75T4YHXV7-MBA/`),
    so this is purely an MDM operational gap, not a config drift.

### Workaround / parallel path: NFS export from desk-nxst-001

If reboots stay deferred and we still need cluster-shared FS on Macs
**now**, the kext-free option is to export `/mnt/juicefs` from desk-nxst-001
via NFS and mount it on each Mac with the macOS built-in NFS client
(no kext, no profile, no AuxKC). desk-nxst-001-side juicefs mount at
`/mnt/juicefs` already works (verified: writes/reads succeed).

Sketch (do NOT implement yet — separate todo item, evaluate after
Stage 1a lands):

```nix
# desk-nxst-001 systems file, x86_64-linux/desk-nxst-001/default.nix
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
`mount_nfs -o nolocks,resvport desk-nxst-001:/mnt/juicefs /Volumes/juicefs-shared`.
Trade: extra hop (Mac → NFS → desk-nxst-001 → JuiceFS → SeaweedFS) vs. direct
(Mac → JuiceFS-FUSE → SeaweedFS), but no kext approval ever needed.

## Cross-cutting notes

- The `claude/seaweedfs-macs` branch carries the macFUSE override
  (`73fe611b`) plus the unrelated git-daemon / sops-nix / observability
  work in `bef53abf`. Once both are merged the mac override stays in
  the system flake until a deliberate post-reboot cleanup commit
  removes it.
- See vault-side `~/Repositories/ocasazza/obsidian/todo.md` for the
  bigger picture: the unblocked Mac JuiceFS mount is on the critical
  path for the Confluence-archive ingest only inasmuch as `desk-nxst-001:~/archive/`
  needs to be reachable from wherever opencode runs. Stage 1a
  (opencode-on-desk-nxst-001) sidesteps this entirely — opencode-on-desk-nxst-001 reads
  the archive **directly** from desk-nxst-001's local filesystem, not via Mac
  JuiceFS. So this section is genuinely independent of the main
  ingest effort and can stay parked until a reboot is convenient.

## Cloud-claude routing through desk-nxst-001's LiteLLM — parked

**Status (2026-04-23):** parked until desk-nxst-001 joins the corp network
(physically on-prem, dropping the need for AppGate VPN).

**What's already in place** (kept ready for activation):

- `local.litellm.passthroughEndpoints.vertex` on desk-nxst-001 →
  `https://vertex-proxy.sdgr.app` with `forwardHeaders = true` and
  `includeSubpath = true`. Once desk-nxst-001 can reach vertex-proxy, this
  endpoint plus virtual-key auth (`x-litellm-api-key` + forwarded
  `Authorization: Bearer <gcloud-id-token>`) gives Phoenix
  per-host attribution for cloud claude calls.
- `local.litellm.routerSettings.modelGroupAlias` populated with
  every Anthropic model id models.dev publishes
  (`claude-{opus,sonnet,haiku}-4-{5,6,7}`) → all alias to
  `coder-cloud-claude` group. Lets clients reference upstream
  model ids without polluting `modelGroups`.
- `dev` team's `models = [...]` allowlist gates on the alias names
  too (LiteLLM enforces team ACL on the raw incoming `model:`
  value, BEFORE alias rewrite). Both layers are ready.
- Per-host virtual keys (`litellm-key-claude-code-darwin`,
  `litellm-key-opencode-darwin`) are minted on desk-nxst-001 and
  sops-encrypted into nixos-config. The
  `programs.claude-code.litellm.cloudPassthrough` toggle on the
  darwin module flips between `vertex.enable=true` (current,
  direct vertex-proxy via Mac VPN tunnel) and the router-routed
  path. Today every darwin host runs vertex-direct
  (`programs.claude-code.vertex.enable = true`) because desk-nxst-001
  can't reach vertex-proxy.

**What was investigated and rejected:**

1. AppGate SDP on desk-nxst-001 (the Linux headless client). Setup is real
   and a working derivation lives in `git reflog | grep
appgate-sdp` (commit `4ed9e2e`, deleted from `feat/appgate-sdp-desk-nxst-001`
   branch on 2026-04-23). Blocker: the corp profile bundle in
   `git-fleet/secrets/.env.prod` is bound to Okta SSO with MFA;
   headless Linux can't complete the interactive login. Would
   require IT to provision a service-account IdP on the AppGate
   Controller for headless servers.
2. SOCKS / SSH tunnel from desk-nxst-001 through one Mac. Works but
   operationally fragile (Mac must stay up + Okta-logged-in).

**Activation steps (when desk-nxst-001 goes on-prem):**

1. Confirm desk-nxst-001 can reach `vertex-proxy.sdgr.app` (`curl
https://vertex-proxy.sdgr.app/` should not be 403'd at the
   network layer — auth-related 401/403 with a real id-token is
   expected and tolerated).
2. Flip `programs.claude-code.vertex.enable = false` and
   `programs.claude-code.litellm.cloudPassthrough = true` in
   `hosts/darwin/default.nix`. Set `litellm.endpoint =
"http://desk-nxst-001:4000"` (already configured).
3. nh switch every darwin host. Smoke-test:
   `claude -p --model claude-opus-4-7 "say OK"`.
4. Verify Phoenix dashboard shows per-host virtual-key attribution
   for the resulting span.

---

## Stage 8 — Atlassian ingest (cme + langgraph throttling)

**Status (2026-04-23, verified by `ssh desk-nxst-001 systemctl status`):** ALL
THREE ingest services (`ingest-atlassian`, `ingest-obsidian`,
`ingest-github`) have been **failing with exit 127** every time their
timer fires, since they were first enabled.

The actual failure mode is **NOT** "credentials missing, skipping"
(my earlier write-up of this todo was wrong — I had only read the
config files and inferred behavior; first verification on 2026-04-23
showed the truth):

```
env: 'bash': No such file or directory
```

The wrapper at `modules/nixos/ingest/default.nix:327-374` calls
`exec ${cfg.projectDir}/scripts/<src>-sync.sh`. The shell script
starts with `#!/usr/bin/env bash`. The systemd unit's PATH (set
implicitly by NixOS systemd defaults — coreutils + findutils +
gnugrep + gnused + systemd, no bash) means `env` runs but can't find
bash → exit 127. The wrapper itself uses an absolute /nix/store
shebang via `pkgs.writeShellScript`, so it gets past its own line 1;
the failure is on the `exec` of the project script.

**This is the same class of bug** as the CLAUDE.md ToDo for
`local.reingest-auto`'s launchd PATH (vault todo, top of "ToDo"
section) — both fail when a script depends on a tool that the
launcher's PATH doesn't include.

**Fix landed in `modules/nixos/ingest/default.nix` 2026-04-23:**
replaced `exec ${cfg.projectDir}/scripts/<src>-sync.sh` with
`exec ${pkgs.bash}/bin/bash ${cfg.projectDir}/scripts/<src>-sync.sh`
for all three sources. Pending `nixos-rebuild switch` on desk-nxst-001.

**State as of 2026-04-23 first verification:**

- `/var/lib/ingest/state.json` does NOT exist — the venv was
  bootstrapped on every failed run (confirmed by `ingest: syncing
deps from ...` log line) but the actual `ingest run-once <src>`
  call was never reached. So no data has ever been pulled, into
  Open WebUI or anywhere else.
- `baseUrl = "https://schrodinger.atlassian.net"` is already set on
  desk-nxst-001's running config (confirmed by reading the wrapper script at
  `/nix/store/...-ingest-atlassian-start`). What was still placeholder
  in main until 2026-04-23: `confluenceSpaces` (`["IT", "OPS"]` →
  narrowed to `["SYSMGR"]`) and `jiraProjects` (`["OPS", "IT"]` →
  narrowed to `[]`).

**Architecture (locked 2026-04-23):**

- **Confluence puller swaps from `pull_confluence` → `cme`**
  ([confluence-markdown-exporter](https://github.com/Spenhouet/confluence-markdown-exporter)).
  The existing `_html_to_markdown` at `projects/ingest/ingest/adapters/atlassian.py:218-229`
  is — by its own admission — a "bare-minimum stripper" that's fine
  for RAG but unworkable for vault writeback. cme is Confluence-aware:
  macros, draw.io, PlantUML, mermaid, attachments, page tree, version
  lockfile.
- **Targets are Confluence URLs, not space-key lists.** Locked:
  `https://schrodinger.atlassian.net/wiki/spaces/itkb` and
  `https://schrodinger.atlassian.net/wiki/spaces/SYSMGR`. The user's
  third URL (End+User+Knowledge+Base subtree) is included by virtue
  of being inside `itkb`.
- **Jira keeps `pull_jira` as-is** (`atlassian.py:152-207`).
- **langgraph IS the throttle.** Every LLM-touching step is a node
  in the existing `graphs/atlassian.py` StateGraph with declared
  `max_concurrency`. No drip-feed counters bolted onto the sink, no
  reingest-auto cadence bumps, no pause sentinels. The orchestrator
  handles queueing, checkpointing, and parallelism; this is what
  langgraph-server on desk-nxst-001 at `:2025` is for.
- **Two sinks fan out from the graph:** `push_to_openwebui` (existing,
  kb-it-docs) and `push_to_vault` (new, GitHub PAT push).
- **reingest-auto is bypassed** for cme content. The launchd agent
  stays as-is for native vault notes; it never sees Confluence
  content. Vault sink writes COMPLETE enriched notes directly to
  `30-Knowledge-Base/IT-Ops/Confluence/<space>/`, NOT stubs to
  `00-Inbox/`.

**Vault side** (`~/Repositories/ocasazza/obsidian/todo.md`) carries
Stage 8a–g (URLs, doctype, flavor, sink contract, first sync, Jira
deferral, capacity-via-langgraph). **This file** carries the infra
pieces: package cme, redirect the systemd unit, secrets, NixOS module
schema for the new sink and target list, observability.

### Stage 8a — get the existing pipeline running at all

The cme + langgraph rewrite (Stages 8b–8g) is irrelevant until the
pipeline runs end-to-end ONCE with the existing code. This stage is
"prove the wiring works against `SYSMGR` with the bare-minimum
`pull_confluence`," then move to the rewrite.

- [x] **Bash-not-in-PATH bug fix** in
      `modules/nixos/ingest/default.nix` (2026-04-23). Both
      `obsidian-sync.sh`, `atlassian-sync.sh`, `github-sync.sh` now
      invoked via `${pkgs.bash}/bin/bash <script>` from the wrapper.
      Pending `nixos-rebuild switch` on desk-nxst-001.
- [x] **desk-nxst-001 config narrowed** to `confluenceSpaces = [ "SYSMGR" ]`
      and `jiraProjects = [ ]` for the first real run
      (2026-04-23). Pending the same rebuild.
- [ ] **`nixos-rebuild switch` on desk-nxst-001**:
  ```sh
  ssh desk-nxst-001 sudo nixos-rebuild switch --flake ~/.config/nixos-config#desk-nxst-001
  ```
  Then immediately:
  ```sh
  ssh desk-nxst-001 sudo systemctl start ingest-atlassian.service
  ssh desk-nxst-001 sudo journalctl -u ingest-atlassian.service -n 200 --no-pager
  ```
  Expected (post-fix): the wrapper completes the venv bootstrap, then
  reaches `ingest run-once atlassian`, and either succeeds (creates
  `/var/lib/ingest/state.json` + new entries in Open WebUI) or fails
  with a NEW error mode that's actually about Atlassian / config /
  network — not exit 127.
- [ ] **Verify Atlassian credentials work** by inspecting the first
      real run's logs. If credentials are wrong, the
      `atlassian-python-api` library raises a 401 — that surfaces in
      the journal as a clear traceback. Rotate at
      <https://id.atlassian.com/manage-profile/security/api-tokens>
      if needed.
- [ ] **Verify state file lands**:
  ```sh
  ssh desk-nxst-001 sudo cat /var/lib/ingest/state.json | jq '.cursors | with_entries(select(.key | startswith("atlassian")))'
  # expect non-empty cursor entries after first successful run
  ```
- [ ] **Smoke-test sink writes**: `curl http://localhost:8080/api/v1/knowledges/`
      on desk-nxst-001; `kb-it-docs` should exist with non-zero file count
      after the first successful Confluence pull. Same for
      `kb-it-tickets` once Jira is re-enabled.
- [ ] **Confirm the other two timers also recover.** The bug
      affected all three sources identically; rebuild fixes all three.
      Verify obsidian + github also exit successfully on next tick.

### Stage 8b — package and integrate cme

- [ ] **Add cme as a project dep** in
      `projects/ingest/pyproject.toml`. cme is on PyPI as
      `confluence-markdown-exporter`. Pin a version (4.0.8 latest as
      of 2026-04-20):
  ```toml
  "confluence-markdown-exporter>=4.0.8,<5",
  ```
  Then `uv lock` to regenerate `uv.lock`. The ingest venv bootstrap
  at `modules/nixos/ingest/default.nix:294-301` does an editable
  install on every service start, so the new dep is picked up at
  next `nixos-rebuild switch`.
- [ ] **Create `projects/ingest/ingest/adapters/confluence.py`**
      (new file, replaces `pull_confluence` in `atlassian.py`).
      Shape:
  - Reads `settings.atlassian_confluence_targets` (URL list — new
    config field, see Stage 8c).
  - Sets cme env vars before invocation:
    - `CME_CONFIG_PATH=/var/lib/ingest/cme-config.json` (per-instance
      config; `cme config set` writes here).
    - `CME_EXPORT__OUTPUT_PATH=/var/lib/ingest/confluence-export`
      (staging dir; one tree per space underneath).
    - `CME_EXPORT__INCLUDE_DOCUMENT_TITLE=false` (Obsidian renders
      title from frontmatter).
    - `CME_EXPORT__PAGE_BREADCRUMBS=false` (Obsidian renders
      parent links natively; we capture parent in frontmatter
      instead).
    - `CME_EXPORT__SKIP_UNCHANGED=true` (default; surfaces lockfile
      diff).
    - `CME_EXPORT__CLEANUP_STALE=true` (deletes pages removed
      upstream — vault sink mirrors this, see Stage 8c).
    - `CME_CONNECTION_CONFIG__MAX_WORKERS=4` (4 parallel HTTP workers
      to Atlassian; default 20 is impolite for a backfill).
    - `CME_EXPORT__LOG_LEVEL=INFO`.
  - Auth via `cme config set auth.confluence.<base-url>.url=...
auth.confluence.<base-url>.username=... auth.confluence.<base-url>.api_token=...`
    on first invocation. Idempotent. Run inside `confluence.py`
    using `subprocess.run(["cme", "config", "set", ...])` if config
    doesn't already have entries — easier than mucking with cme's
    URL-keyed nested dict directly.
  - For each URL in `confluence_targets`, shell out to
    `cme spaces <url>` (or `cme pages-with-descendants <url>` if
    the URL is a page-with-descendants shape). Capture stdout/stderr
    to the systemd journal.
  - After cme run, read the lockfile diff
    (`/var/lib/ingest/confluence-export/confluence-lock.json`)
    against the previous-run snapshot stored in
    `state.json["cursors"]["atlassian:confluence:lockfile"]`. The
    diff yields the list of (page_id, version) tuples that need to
    be enriched.
  - Yield those as `ConfluencePageDoc` dataclasses (similar to
    `AtlassianDoc`), each carrying the cme-emitted markdown body,
    cme-emitted frontmatter, the source URL, parent breadcrumbs,
    attachment list, and the staging-dir path.
- [ ] **Delete `pull_confluence` and `_html_to_markdown` from
      `adapters/atlassian.py`.** Keep `pull_jira` and the file. Add
      a top-of-file comment pointing to the new `confluence.py`.
      Rename the file to `jira.py` if the package layout
      consistency matters; otherwise leave it (the import paths in
      the graph determine the public surface).
- [ ] **Rewire `graphs/atlassian.py`** per the vault todo Stage 8g
      "Revised graph shape" diagram:
  ```
  pull_jira → push_jira_to_openwebui
  cme_export_confluence → diff_lockfile → enrich_page (Send fan-out, max_concurrency=2)
                                            ├→ push_to_openwebui
                                            └→ push_to_vault
  summarize_run → END
  ```
  Use `langgraph.types.Send` for the per-page fan-out from
  `diff_lockfile` to `enrich_page`. Compile with
  `compile(checkpointer=MemorySaver(), interrupt_before=[])` —
  checkpointing means a graph that's killed mid-backfill resumes
  from the last completed `enrich_page`.
- [ ] **`enrich_page` node** is the only LLM call per page. Reads
      `page.body`, calls LiteLLM (model
      `INGEST_ENRICH_MODEL=coder-local` by default) with the
      enrichment prompt (TBD, lives in vault at
      `vault/40-Prompt-Library/Ingest-Flavors/confluence-page.md`
      body). Returns the enriched markdown (original body +
      `## Summary` + `## Related` wikilinks). Concurrency cap:
      `INGEST_ENRICH_MAX_CONCURRENCY=2` (env-driven, applied as
      langgraph node-level concurrency).
- [ ] **Test the new graph in `langgraph dev`** before
      production-enabling. The langgraph-server module already
      runs `ingest` at `:2025`; visit
      `http://desk-nxst-001:2025/info` to confirm the new `atlassian`
      graph shape, then click through a single-page run in the
      Studio UI.

### Stage 8c — NixOS module schema changes

`modules/nixos/ingest/default.nix` needs three additions:

- [ ] **New atlassian source option** `confluenceTargets`:
  ```nix
  confluenceTargets = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      (atlassian) Confluence URLs to sync via cme. Each URL is
      either a space (.../wiki/spaces/SPACEKEY), a page-with-
      descendants subtree (.../wiki/spaces/SPACEKEY/pages/ID/Title),
      or a single page (same URL shape but invoked via cme pages).
      cme infers the kind from the URL.
    '';
  };
  ```
  Add the `INGEST_ATLASSIAN_CONFLUENCE_TARGETS` env export to the
  atlassian start-script wrapper at `default.nix:349-363`. JSON
  list (use `builtins.toJSON` like the github repos field does at
  `default.nix:312-322`).
- [ ] **New `cfg.sinks.vaultGithub` sink submodule** mirroring the
      openwebui sink shape (`url=https://api.github.com`, `tokenFile`,
      `repo="ocasazza/obsidian"`, `branch="main"`, `vaultRoot="vault"`,
      `targetDir="30-Knowledge-Base/IT-Ops/Confluence"`,
      `attachmentsDir="90-Attachments/Confluence"`). NB: NOT a
      `dropDir` to `00-Inbox/` — the langgraph-as-throttle decision
      means writes are complete enriched notes, not stubs.
- [ ] **New writer-PAT secret**:
      `secrets/obsidian-vault-writer-token.yaml`. Fine-grained GitHub
      PAT scoped to `ocasazza/obsidian` with `Contents: Read and
write` permission. Wire as `cfg.sinks.vaultGithub.tokenFile`,
      exported into the atlassian start-script wrapper as
      `INGEST_VAULT_GITHUB_TOKEN` at the last possible moment (matches
      the secret-handling pattern at `default.nix:330-335`).

### Stage 8d — separate LiteLLM virtual key for ingest

To prevent ingest from starving interactive opencode/swarm requests:

- [ ] **New sops secret** `secrets/litellm-virtual-key-ingest.yaml`
      containing a LiteLLM virtual key distinct from the existing
      `LITELLM_OPENCODE_KEY`.
- [ ] **Update LiteLLM config** (path TBD — find via
      `rg LITELLM_OPENCODE_KEY systems/x86_64-linux/desk-nxst-001/`). Add the
      ingest key with:
  - `rpm_limit: 60` (60 requests per minute hard ceiling, regardless
    of what the graph requests).
  - **Defer** the `priority: low` per-key routing until interactive
    opencode visibly queues behind ingest work. The graph-level
    concurrency cap + rpm limit cover the practical cases.
- [ ] **Wire the key into the atlassian sync wrapper** as
      `INGEST_LITELLM_KEY`. The `enrich_page` node uses this key
      when calling LiteLLM at `localhost:4000`.

### Stage 8e — Open WebUI duplication policy

The same Confluence page now lands in both Open WebUI (`kb-it-docs`)
and the vault. Then the obsidian ingest adapter (running every 15 min)
notices the new vault note and pushes it AGAIN into `kb-it-docs` per
`defaultObsidianFolderMap` at `modules/nixos/ingest/default.nix:64-73`.

- [ ] **Decide**:
  - (a) Keep both — accept duplicate documents in `kb-it-docs` (one
    cme-rendered raw body, one vault-enriched note with `## Summary`
    - `## Related`). LLM dedupes on retrieval. Wasteful but simple.
  - (b) Route Confluence-source notes to a separate knowledge
    (`kb-it-docs-vault` for vault-shape, `kb-it-docs` stays cme-raw).
    Loses cross-source RAG.
  - (c) Have the `push_to_openwebui` node SKIP cme content (since the
    vault path will end up in `kb-it-docs` via the obsidian adapter
    anyway). Cleanest long-term, requires the graph to know about the
    obsidian adapter's eventual path. Most aligned with
    "langgraph orchestrates everything."
  - **Lean (c)** but punt the implementation to after Stage 8b proves
    the vault path actually works. (a) is the interim default; if you
    forget to flip it, you get redundant docs in `kb-it-docs`, not
    broken behavior.

### Stage 8f — observability

The ingest module wires Phoenix/OTLP for the LangGraph spans already
(`config.py`, `telemetry.py`, env `INGEST_PHOENIX_ENDPOINT`). What's
missing is per-source success/failure metrics in Prometheus AND the
backpressure visibility called out in the vault todo Stage 8g.

- [ ] **Atlassian sync metrics** (textfile pattern, mirror of
      `scripts/reingest-auto.sh`):
      `atlassian_last_run_timestamp_seconds`,
      `atlassian_documents_pushed_total{kind=jira|confluence,sink=openwebui|vault}`,
      `atlassian_last_exit_code`, `atlassian_cme_pages_changed_total`,
      `atlassian_cme_pages_skipped_total`. Drop to
      `/var/lib/node_exporter/textfile/atlassian.prom` from the
      atlassian-sync.sh wrapper.
- [ ] **langgraph node concurrency** — surface
      `enrich_page` in-flight count via Phoenix span counts. The
      `openinference-instrumentation-langchain` already in
      `pyproject.toml:43` emits these; just add a Grafana panel
      pulling from Phoenix's Prometheus endpoint at `:6006`.
- [ ] **vLLM saturation** panels:
  - `vllm:num_running_requests` — should oscillate around the
    enrich-node concurrency cap during a backfill.
  - `vllm:num_waiting_requests` — alert on `> 0` for more than 5 min
    during interactive hours.
  - `vllm:gpu_cache_usage_perc` — alert >85%.
- [ ] **Confluence backlog** — count of pages in cme lockfile not
      yet pushed to vault. Sink emits via the textfile path; one new
      gauge `atlassian_vault_backlog_pages`. Goes to zero in
      steady-state.
- [ ] **GPU temp delta vs. interactive baseline** — pre-existing
      thermal panel; add a recording rule for "delta vs. yesterday's
      no-ingest hour mean" so the dashboard has a clear "yes the
      backfill is running hot" signal.
- [ ] **Add a `desk-nxst-001-stack` Grafana dashboard panel** for atlassian
      ingest health. Mirrors the existing reingest panels per CLAUDE.md
      "Observability / Dashboards". File:
      `modules/nixos/observability/dashboards/desk-nxst-001-stack-panels.md` —
      add a row under "ingest health" for atlassian timer freshness +
      document throughput + the new vLLM saturation panels above.

### Stage 8g — first-backfill scheduling

For the FIRST backfill only (until cme reports `Skipped N pages
(unchanged)` for the bulk):

- [ ] **Off-hours `OnCalendar` override**: temporarily set
      `services.timers.ingest-atlassian.timerConfig.OnCalendar =
"02:00..06:00/0:30"` (every 30 min between 2 AM and 6 AM) on
      desk-nxst-001. Lasts for the duration of the first sync (~2-3 nights
      per the vault-side capacity estimate).
- [ ] **Revert to `*:0/30`** after `vllm_num_waiting_requests` stays
      at zero during a daytime test pull, OR three consecutive
      no-bulk-change nights. Whichever first.

---

## Stage 9 — langflow on desk-nxst-001

**Decision (locked 2026-04-23 in vault todo Stage 9):** enable the
existing langflow module on desk-nxst-001. Routes through LiteLLM at
`localhost:4000` like everything else. CLAUDE.md ToDo entry "Wire
langflow as an ingest backend" gets struck once this lands.

The module already exists at `modules/nixos/langflow/default.nix` —
fully written (uv venv, sqlite/postgres options, OTEL wiring),
just never imported. The CLAUDE.md note saying "likely a new
modules/nixos/langflow/ module" at line 405 is stale.

### Stage 9a — turn it on

- [ ] **Import + enable** in `systems/x86_64-linux/desk-nxst-001/default.nix`:
  ```nix
  local.langflow = {
    enable = true;
    port = 7860;
    openFirewall = true;          # LAN, mirrors langgraphServer.swarm at :2024
    database = "sqlite";          # postgres later if durability matters
    openaiApiBase = "http://127.0.0.1:4000/v1";  # LiteLLM
    openaiApiKeyFile = config.sops.secrets.litellm-virtual-key-langflow.path;
    otelEndpoint = "http://127.0.0.1:4317";
  };
  ```
  (Adjust to match the actual option names in
  `modules/nixos/langflow/default.nix` — read the module first; the
  shape above is illustrative.)
- [ ] **Provision LiteLLM virtual key** for langflow:
      `secrets/litellm-virtual-key-langflow.yaml`. New sops secret. The
      pattern mirrors `LITELLM_OPENCODE_KEY` — see CLAUDE.md "LiteLLM
      virtual key on desk-nxst-001" risk in vault todo Stage 1.
- [ ] **`nixos-rebuild switch`**, verify:
  ```sh
  systemctl status langflow.service
  curl http://desk-nxst-001:7860/api/v1/health  # langflow health endpoint
  ```
- [ ] **CLAUDE.md update**: strike the "Wire langflow as an ingest
      backend" ToDo at line 405. Add langflow to the orchestrator
      inventory (joins `langgraphServer` and the planned
      `langgraphOci`).

### Stage 9b — flavor + opencode wiring

(see vault todo Stage 9 for the flavor file rewrite — it's vault-side
work)

- [ ] If langflow exposes an OpenAI-compatible chat endpoint (it does,
      via the playground), add it as a third provider in
      `~/Repositories/ocasazza/obsidian/.opencode/opencode.json`. Per the
      CLAUDE.md "Provider-prefix rule": `model: langflow/<model-id>`.
      This lets opencode commands pin langflow as a backend explicitly.
- [ ] Otherwise, wire langflow as an MCP server in
      `~/.config/opencode/opencode.json` so the LLM can call into langflow
      to fetch flow definitions / trigger runs. Decide based on what
      langflow flows actually _do_ in this stack — TBD pending Stage 9a
      verification.

---

## Stage 10 — graphify infra (was deferred to vault todo Stage 6)

The vault-side todo Stage 6 is the canonical plan for `/graphify` as
an opencode slash command + `graph-cluster` doctype. Infra side here
just covers what graphify needs from the runtime that doesn't already
exist.

### Stage 10 status

- The graphify CLI is packaged at
  `~/Repositories/ocasazza/obsidian/nix/packages/graphify/default.nix`
  (118 lines, `pname = "graphifyy"`, vendors 6 of 16 tree-sitter
  parsers after `postPatch`). Available in `nix develop` and
  `nix develop .#full` as `ns.graphify`.
- The desk-nxst-001 comment at `systems/x86_64-linux/desk-nxst-001/default.nix:997` is
  the only nixos-config reference, and it's purely aspirational:
  _"The point of running opencode here at all is to drive the
  archive ingestion + graphify pipelines (vault todo Stages 5-6)
  using the local vLLM."_
- No service, no module, no launchd / systemd unit, no port for
  graphify in any host config.

### Stage 10a — does graphify need to be a service?

- [ ] **Decide**: graphify is a CLI; the vault-side `/graphify`
      opencode command can shell out to it. No need for a service.
      HOWEVER, if you want graphify runs to be scheduled (e.g.
      weekly cluster refresh of `30-Knowledge-Base/`), wrap it in a
      systemd timer on desk-nxst-001 similar to the ingest timers. Sketch:
  ```nix
  systemd.services.graphify-refresh = {
    description = "Weekly /graphify pass over the vault checkout";
    serviceConfig.Type = "oneshot";
    serviceConfig.User = "ingest";
    script = ''
      exec ${pkgs.opencode}/bin/opencode run "/graphify 30-Knowledge-Base/"
    '';
  };
  systemd.timers.graphify-refresh = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "Sun 03:00"; Persistent = true; };
  };
  ```
  Defer until vault todo Stage 6 is implemented; this is just a
  placeholder so the infra side doesn't lose it.

### Stage 10b — graphify Qdrant integration

- [ ] If vault todo Stage 10's "fetch embedding by external_id rather
      than re-embedding" optimization lands, graphify needs Qdrant API
      access. The Qdrant service from vault todo Stage 2 listens on
      `:6333` (HTTP) on desk-nxst-001; the graphify CLI invocation in the
      systemd timer above must include `QDRANT_URL=http://localhost:6333`
      in its env.

---

## Cross-cutting notes (continued from above)

- **Atlassian backfill capacity.** Vault todo Stage 8g now carries
  the canonical capacity model (langgraph-orchestrated, node-level
  `max_concurrency=2`, ~10h wall clock for ~2,500 pages). The
  binding constraint is desk-nxst-001's vLLM, not Atlassian's API. Open
  WebUI's file ingest uses an embedding model (currently NOT served
  by desk-nxst-001's vLLM — see CLAUDE.md "Embeddings" ToDo at line 416),
  so the OpenWebUI sink path goes through Open WebUI's RAG default
  embedder. The langgraph `enrich_page` node is the dominant LLM
  cost; the OpenWebUI embedding pass is the secondary one.
- **Sops secret naming convention** for the new entries:
  - `secrets/atlassian-email.yaml` ✅ (exists; user states real value)
  - `secrets/atlassian-api-token.yaml` ✅ (exists; user states real value)
  - `secrets/obsidian-vault-writer-token.yaml` (new, Stage 8c)
  - `secrets/litellm-virtual-key-ingest.yaml` (new, Stage 8d)
  - `secrets/litellm-virtual-key-langflow.yaml` (new, Stage 9a)
    All follow the existing pattern (one secret per file, key matches
    filename basename without `-` underscores per `.sops.yaml`).
