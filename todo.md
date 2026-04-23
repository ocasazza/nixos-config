# todo.md — infra side

Cross-agent coordination doc. Companion file:
`~/Repositories/ocasazza/obsidian/todo.md` (vault side). Both must stay in
sync; if you change one, glance at the other.

**Last updated:** 2026-04-23 (added Stage 8 atlassian, Stage 9 langflow, Stage 10 graphify)
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
    The host _is_ declared in nix (`systems/aarch64-darwin/L75T4YHXV7-MBA/`),
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

---

## Stage 8 — Atlassian ingest (currently silently failing)

**Status (2026-04-23):** the atlassian source in `local.ingest` is
**already enabled on luna** with placeholder credentials. The systemd
timer `ingest-atlassian.timer` has been firing every 30 min returning
"credentials missing, skipping" since the source was first wired.
Discovered during a vault-side ingest survey on 2026-04-23.

The pipeline itself is fully implemented — `projects/ingest/ingest/adapters/atlassian.py:152-320`
covers Jira (JQL `updated >= cursor`, 50/page) and Confluence (CQL
`lastModified >= cursor`, ADF→md + HTML→md), with per-project / per-space
cursors in `/var/lib/ingest/state.json` and the same idempotent push-by-
external-id flow as obsidian/github. The only thing missing is real
credentials.

**Vault side carries Stage 8a–8e** (doctype, flavor, vault sink, first
sync, Jira deferral). This file carries the infra pieces.

### Stage 8a — turn on real Atlassian credentials

- [ ] **Decrypt and rotate**
      `secrets/atlassian-email.yaml` and
      `secrets/atlassian-api-token.yaml`. Both files exist as encrypted
      sops blobs but contain placeholder values — confirm by
      `sops -d secrets/atlassian-api-token.yaml`. Generate a real API
      token at <https://id.atlassian.com/manage-profile/security/api-tokens>
      scoped to "API token" (not OAuth). Replace the value, re-encrypt,
      commit.
- [ ] **Set the real tenant URL** in
      `systems/x86_64-linux/luna/default.nix:919`:
      `baseUrl = "https://yourdomain.atlassian.net"` → real value.
      This is currently the literal placeholder string. Without this,
      the adapter never even attempts a connection.
- [ ] **Cap the project / space lists** at
      `systems/x86_64-linux/luna/default.nix:923-930` to a known-small
      subset for the first run (one Jira project, one Confluence space)
      to avoid an uncapped backfill into Open WebUI before the vault
      sink is ready. Currently `["OPS", "IT"]` on both sides.
- [ ] **`nixos-rebuild switch`** on luna, then verify in this order:
  ```sh
  systemctl status ingest-atlassian.service
  journalctl -u ingest-atlassian.service -n 200 --no-pager
  # expect to see e.g.
  #   pull_jira: backfilling N issues for project=OPS (cursor: empty)
  #   pull_confluence: backfilling N pages for space=IT (cursor: empty)
  cat /var/lib/ingest/state.json | jq '.cursors | with_entries(select(.key | startswith("atlassian")))'
  # expect non-empty cursor entries after first run
  ```
- [ ] **Smoke-test sink writes**: `curl http://localhost:8080/api/v1/knowledges/`
      on luna; the `kb-it-tickets` and `kb-it-docs` knowledges should
      exist with non-zero file counts.

### Stage 8b — vault sink in `projects/ingest/`

(See vault todo Stage 8b for the data contract; this section tracks
infra deps.)

- [ ] **Choose write path**:
  - (i) New `projects/ingest/ingest/sinks/vault_local.py` that writes
    to a local checkout — requires the vault to be checked out on
    luna AND requires reconciling with vault-snapshot (which runs on
    Mac and is the sole writer per CLAUDE.md "Sync / backup"). Strong
    risk of resurrecting the silent-revert bug from 2026-04-22
    (commits `565a427` and `2473ea9`). **Reject.**
  - (ii) New `projects/ingest/ingest/sinks/vault_github.py` that
    pushes via the GitHub Contents API directly (mirror of how the
    `obsidian` adapter _reads_ — see `adapters/obsidian.py:48`).
    Requires a writer-PAT in sops on luna. No local checkout. Plays
    cleanly with vault-snapshot (the next snapshot from Mac picks
    these up via `obsidian-git autoPullInterval: 5`). **Lean (ii).**
- [ ] **Add a `vault_github` writer-PAT secret**: new
      `secrets/obsidian-vault-writer-token.yaml` containing a fine-grained
      GitHub PAT scoped to `ocasazza/obsidian` with `Contents: Read and
write` permission. Wire it through the ingest module as
      `cfg.sinks.vaultGithub.tokenFile`.
- [ ] **Extend the ingest NixOS module**
      (`modules/nixos/ingest/default.nix`):
  - New `cfg.sinks.vaultGithub` submodule mirroring the openwebui
    sink shape (`url`, `tokenFile`, `repo`, `branch`, `vaultRoot`,
    `dropDir = "00-Inbox"`). The default `dropDir` is the inbox so
    the existing `local.reingest-auto` agent picks the stubs up via
    the `ingest/auto` tag flow — matches the "lean (ii)" decision
    in vault todo Stage 8b.
  - Wire the token export into the atlassian start-script wrapper at
    `default.nix:349-363`.
- [ ] **Coordinate cadence**: if the atlassian timer is `*:0/30` and
      the Mac-side `local.reingest-auto` is hourly, there's up to a
      ~90 min lag between Confluence edit → vault note enrichment. Fine
      for first cut; tighten later.

### Stage 8c — Open WebUI duplication policy

The same Confluence page now lands in both Open WebUI (`kb-it-docs`)
and the vault (via the GitHub PAT push → opencode reingest →
`30-Knowledge-Base/IT-Ops/Confluence/<space>/`). Then the obsidian
ingest adapter (running every 15 min via `ingest-obsidian.timer`)
notices the new vault note and pushes it AGAIN into a vault-side
knowledge (currently `kb-it-docs` per `defaultObsidianFolderMap` at
`modules/nixos/ingest/default.nix:64-73`).

- [ ] **Decide**:
  - (a) Keep both — accept duplicate documents in `kb-it-docs` (one
    raw Confluence body, one enriched vault note). LLM dedupes on
    retrieval. Wasteful but simple.
  - (b) Route Confluence-source notes to a separate knowledge
    (`kb-it-docs-vault` for vault-shape, `kb-it-docs` stays raw).
    Loses cross-source RAG.
  - (c) Have the atlassian adapter SKIP the Open WebUI sink for any
    page whose content will be enriched by the vault path. Requires
    the atlassian adapter to know about the vault sink's existence.
    Most aligned long-term.
  - **Lean (c)** but punt the implementation to after Stage 8b
    proves the vault path actually works. (a) is the interim default.

### Stage 8d — observability

The ingest module wires Phoenix/OTLP for the LangGraph spans already
(`config.py:telemetry.py`, env `INGEST_PHOENIX_ENDPOINT`). What's
missing is per-source success/failure metrics in Prometheus.

- [ ] **Add a `reingest`-style textfile metric for atlassian sync**
      (mirror of `scripts/reingest-auto.sh`'s pushgateway pattern in the
      vault repo, see CLAUDE.md "Observability / Reingest signal"). Drop
      `atlassian_last_run_timestamp_seconds`,
      `atlassian_documents_pushed_total{kind=jira|confluence}`,
      `atlassian_last_exit_code` to the local node_exporter textfile
      collector at `/var/lib/node_exporter/textfile/atlassian.prom`.
      The atlassian-sync.sh wrapper at
      `projects/ingest/scripts/atlassian-sync.sh` is the natural spot.
- [ ] **Add a `luna-stack` Grafana dashboard panel** for atlassian
      ingest health. Mirrors the existing reingest panels per CLAUDE.md
      "Observability / Dashboards". File:
      `modules/nixos/observability/dashboards/luna-stack-panels.md` —
      add a row under "ingest health" for atlassian timer freshness +
      document throughput.

---

## Stage 9 — langflow on luna

**Decision (locked 2026-04-23 in vault todo Stage 9):** enable the
existing langflow module on luna. Routes through LiteLLM at
`localhost:4000` like everything else. CLAUDE.md ToDo entry "Wire
langflow as an ingest backend" gets struck once this lands.

The module already exists at `modules/nixos/langflow/default.nix` —
fully written (uv venv, sqlite/postgres options, OTEL wiring),
just never imported. The CLAUDE.md note saying "likely a new
modules/nixos/langflow/ module" at line 405 is stale.

### Stage 9a — turn it on

- [ ] **Import + enable** in `systems/x86_64-linux/luna/default.nix`:
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
      virtual key on luna" risk in vault todo Stage 1.
- [ ] **`nixos-rebuild switch`**, verify:
  ```sh
  systemctl status langflow.service
  curl http://luna.local:7860/api/v1/health  # langflow health endpoint
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
- The luna comment at `systems/x86_64-linux/luna/default.nix:997` is
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
      systemd timer on luna similar to the ingest timers. Sketch:
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
      `:6333` (HTTP) on luna; the graphify CLI invocation in the
      systemd timer above must include `QDRANT_URL=http://localhost:6333`
      in its env.

---

## Cross-cutting notes (continued from above)

- **Atlassian backfill capacity.** First-time Confluence sync on a
  large space (e.g. a 1000+ page corporate space) at the default
  `initial_backfill_days = 30` could pull hundreds of pages on the
  first tick. Open WebUI's file ingest uses an embedding model
  (currently NOT served by luna's vLLM — see CLAUDE.md "Embeddings"
  ToDo at line 416), so the first backfill goes through whatever
  embedder Open WebUI's RAG config defaults to. Watch for slow runs;
  consider lowering backfill to 7 days for the very first sync.
- **Sops secret naming convention** for the new entries:
  - `secrets/atlassian-email.yaml` ✅ (exists, placeholder)
  - `secrets/atlassian-api-token.yaml` ✅ (exists, placeholder)
  - `secrets/obsidian-vault-writer-token.yaml` (new, Stage 8b)
  - `secrets/litellm-virtual-key-langflow.yaml` (new, Stage 9a)
    All follow the existing pattern (one secret per file, key matches
    filename basename without `-` underscores per `.sops.yaml`).
