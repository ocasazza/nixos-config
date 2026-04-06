#!/usr/bin/env bash
# deploy-cluster.sh — commit, push via colmena, then activate on all nodes.
# Usage: ./scripts/deploy-cluster.sh [hostname...]
#   If no hostnames are given, deploys to all reachable cluster nodes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

# ── 1. Commit & push ────────────────────────────────────────────────────────
cd "$REPO_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "==> Committing local changes..."
  git add -A
  git commit -m "chore: deploy cluster config $(date '+%Y-%m-%d %H:%M')"
fi
echo "==> Pushing..."
git push

# ── 2. Colmena: build & push closures ───────────────────────────────────────
COLMENA_TARGETS=$(IFS=,; echo "${TARGETS[*]}")
echo "==> Colmena push to: $COLMENA_TARGETS"
nix run github:zhaofengli/colmena -- apply \
  --on "$COLMENA_TARGETS" \
  --no-substitute \
  push 2>&1

# ── 3. Activate on each node ─────────────────────────────────────────────────
FAILED=()
for host in "${TARGETS[@]}"; do
  ip="${NODE_IPS[$host]:-}"
  echo ""
  echo "==> Activating $host..."

  if [ "$host" = "$LOCAL_HOSTNAME" ] || [ "$ip" = "localhost" ]; then
    # Local activation
    if nh darwin switch ".#$host" 2>&1; then
      echo "  OK: $host (local)"
    else
      echo "  FAILED: $host (local activation)"
      FAILED+=("$host (local activation failed)")
    fi
    continue
  fi

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "casazza@$ip" true 2>/dev/null; then
    echo "  SKIP: $host ($ip) unreachable"
    FAILED+=("$host (unreachable)")
    continue
  fi

  # Remote: run nix-darwin activation via the already-pushed closure
  if ssh "casazza@$ip" bash -s -- "$host" <<'REMOTE'
    set -euo pipefail
    HOSTNAME="$1"
    # Find the latest system profile and activate it
    system_profile="/nix/var/nix/profiles/system"
    if [ -L "$system_profile" ]; then
      echo "  Running activate..."
      sudo "$system_profile/activate" 2>&1
      "$system_profile/activate-user" 2>&1 || true
    else
      echo "  No system profile found — falling back to nh darwin switch"
      cd "$HOME/.config/nixos-config" && nh darwin switch ".#$HOSTNAME"
    fi
REMOTE
  then
    echo "  OK: $host"
  else
    echo "  FAILED: $host"
    FAILED+=("$host (activation failed)")
  fi
done

# ── 4. Summary ───────────────────────────────────────────────────────────────
echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "==> All nodes deployed and activated."
else
  echo "==> Done with errors:"
  for f in "${FAILED[@]}"; do echo "    - $f"; done
  exit 1
fi
