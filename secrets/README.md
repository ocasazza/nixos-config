# Secrets — rotation procedure

## Trust hierarchy

Three layers, enforced by key-management flow rather than by sops itself.
An **offline root key** (never used operationally, kept air-gapped) signs
**admin keys** out-of-band. Any single admin can encrypt or decrypt every
secret in this tree (Atlassian creds, OpenWebUI tokens, GitHub PATs, etc.).
**Host keys** are derived from each consumer host's SSH host key via
`ssh-to-age`; sops-nix decrypts at nixos-rebuild activation with no
private-key copy. Sops sees all recipients as equal — the admin/host
distinction is intent, not a cryptographic constraint.

Authoritative anchor list: [`../.sops.yaml`](../.sops.yaml).

## Adding a new admin

1. New admin generates an age key on their machine:
   `age-keygen -o ~/.config/sops/age/keys.txt`
2. **Root-signs the new pubkey out-of-band** (offline root key, tracked
   separately — not in this repo).
3. New admin shares the pubkey out-of-band (Signal, Keybase, in person).
4. An existing admin appends the pubkey to the `&admin_<name>` anchor
   list in `.sops.yaml` and adds `*admin_<name>` to every relevant
   `creation_rules` entry (or `key_groups` entry for multi-recipient
   files).
5. Existing admin runs, from the repo root:
   ```
   sops updatekeys --yes secrets/*.yaml secrets/*.env
   ```
6. Commit and push.

## Adding a new host

1. On the new host: `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`.
2. Append the output under a `&host_<name>` anchor in `.sops.yaml` and
   add `*host_<name>` to the relevant `creation_rules` / `key_groups`
   entries for the secrets that host consumes.
3. `sops updatekeys --yes secrets/*.yaml secrets/*.env`, commit, push.
4. Wire the host's NixOS config to point sops-nix at
   `/etc/ssh/ssh_host_ed25519_key` (sops-nix default `sshKeyPaths`).

## Rotating an admin key (compromise, departure)

1. Remove the compromised admin's pubkey from `.sops.yaml` (delete the
   `&admin_<name>` anchor and any `*admin_<name>` references).
2. `sops updatekeys --yes secrets/*.yaml secrets/*.env` — this re-
   encrypts so the removed key can no longer decrypt new ciphertext.
3. Commit and push.
4. **Rotate every credential the departed admin had read access to**
   (regenerate API tokens, invalidate the old values upstream). The
   old ciphertext is still decryptable by the compromised key offline
   against history, so the only real remediation is to invalidate the
   plaintext at the source.

## Rotating the offline root

Rare. The root's job is to attest to admin pubkeys; no sops ciphertext
is encrypted to the root directly. To rotate:

1. Generate a new offline root on an air-gapped machine.
2. Re-sign all current admin pubkeys with the new root (out-of-band).
3. Update the root-fingerprint comment in `.sops.yaml`.
4. No `sops updatekeys` pass is needed — sops files are unchanged.

## Editing a secret

```
sops edit secrets/<name>.yaml
```

Don't edit the encrypted files directly — sops won't re-seal them
correctly, the MAC will fail, and sops-nix will refuse to activate.
