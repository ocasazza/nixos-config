#!/usr/bin/env bash
# deploy-cluster.sh — commit, build closures, then activate all nodes in parallel.
# Usage: nix run .#deploy-cluster [hostname...]
#   If no hostnames are given, deploys to all reachable cluster nodes.
set -euo pipefail

# When run as a Nix app the script lives in the store, not the repo.
# Fall back to $PWD (user must run from repo root) or accept REPO_DIR env override.
if [[ -n "${REPO_DIR:-}" ]]; then
  : # already set
elif git -C "$PWD" rev-parse --show-toplevel &>/dev/null; then
  REPO_DIR="$(git -C "$PWD" rev-parse --show-toplevel)"
else
  echo "error: cannot find nixos-config repo. Run from the repo root or set REPO_DIR." >&2
  exit 1
fi

LOCAL_HOSTNAME="$(hostname -s)"

CLUSTER_NODES=(
  "GN9CFLM92K-MBP"
  "CK2Q9LN7PM-MBA"
  "GJHC5VVN49-MBP"
  "L75T4YHXV7-MBA"
)

declare -A NODE_IPS=(
  ["GN9CFLM92K-MBP"]="localhost"
  ["CK2Q9LN7PM-MBA"]="192.168.1.3"
  ["GJHC5VVN49-MBP"]="192.168.1.56"
  ["L75T4YHXV7-MBA"]="L75T4YHXV7-MBA.local"
)

TARGETS=("${@:-${CLUSTER_NODES[@]}}")
LOG_DIR="$(mktemp -d /tmp/deploy-cluster.XXXXXX)"
trap 'rm -rf "$LOG_DIR"' EXIT

# ── 1. Commit & push ────────────────────────────────────────────────────────
cd "$REPO_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "==> Committing local changes..."
  git add -A
  git commit -m "chore: deploy cluster config $(date '+%Y-%m-%d %H:%M')"
fi
echo "==> Pushing..."
git push

# ── 2. Build all closures in parallel (Nix handles concurrency via max-jobs) ─
echo "==> Building closures for: ${TARGETS[*]}"
BUILD_ATTRS=()
for host in "${TARGETS[@]}"; do
  BUILD_ATTRS+=(".#darwinConfigurations.${host}.system")
done
nix build --no-link "${BUILD_ATTRS[@]}"

# ── 3. Copy closures to remote nodes in parallel ─────────────────────────────
echo "==> Copying closures to remote nodes..."
COPY_PIDS=()
for host in "${TARGETS[@]}"; do
  ip="${NODE_IPS[$host]:-}"
  [[ "$host" == "$LOCAL_HOSTNAME" || "$ip" == "localhost" ]] && continue
  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "casazza@${ip}" true &>/dev/null; then
    echo "  SKIP (unreachable): $host"
    continue
  fi
  closure="$(nix path-info ".#darwinConfigurations.${host}.system")"
  nix copy --to "ssh://casazza@${ip}" "$closure" &
  COPY_PIDS+=($!)
done
for pid in "${COPY_PIDS[@]}"; do wait "$pid"; done

# ── 4. Activate on all nodes in parallel via mprocs ──────────────────────────
echo ""
echo "==> Activating ${#TARGETS[@]} nodes in parallel..."

MPROCS_CMDS=()

for host in "${TARGETS[@]}"; do
  ip="${NODE_IPS[$host]:-}"
  status_file="$LOG_DIR/${host}.status"
  activate_script="$LOG_DIR/${host}.sh"
  closure="$(nix path-info ".#darwinConfigurations.${host}.system" 2>/dev/null || echo "")"

  if [[ "$host" == "$LOCAL_HOSTNAME" || "$ip" == "localhost" ]]; then
    cat > "$activate_script" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "==> $host (local)"
if sudo "${closure}/sw/bin/darwin-rebuild" activate 2>&1; then
  echo "OK" > "${status_file}"
  echo "  OK: $host"
else
  echo "FAILED" > "${status_file}"
  echo "  FAILED: $host"
  exit 1
fi
SCRIPT
  else
    cat > "$activate_script" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "==> $host ($ip)"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "casazza@${ip}" true 2>/dev/null; then
  echo "SKIP" > "${status_file}"
  echo "  SKIP: $host unreachable"
  exit 0
fi
ssh "casazza@${ip}" bash -s << 'INNEREOF' || { echo "FAILED" > "${status_file}"; exit 1; }
set -euo pipefail
profile="${closure}"
[ -e "\$profile" ] || { echo "closure not found on remote"; exit 1; }
sudo "\$profile/activate" 2>&1
"\$profile/activate-user" 2>&1
INNEREOF
echo "OK" > "${status_file}"
echo "  OK: $host"
SCRIPT
  fi

  chmod +x "$activate_script"
  MPROCS_CMDS+=("$host=$activate_script")
done

mprocs --no-docs "${MPROCS_CMDS[@]}"

# ── 5. Summary ───────────────────────────────────────────────────────────────
echo ""
FAILED=()
SKIPPED=()
for host in "${TARGETS[@]}"; do
  status="$(cat "$LOG_DIR/${host}.status" 2>/dev/null || echo "UNKNOWN")"
  case "$status" in
    OK)      echo "  [OK]   $host" ;;
    SKIP)    echo "  [SKIP] $host (unreachable)"; SKIPPED+=("$host") ;;
    FAILED)  echo "  [FAIL] $host"; FAILED+=("$host") ;;
    UNKNOWN) echo "  [???]  $host"; FAILED+=("$host") ;;
  esac
done

echo ""
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "==> Skipped: ${SKIPPED[*]}"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "==> All reachable nodes deployed and activated."
else
  echo "==> Failed: ${FAILED[*]}"
  exit 1
fi
