#!/usr/bin/env bash
# deploy-cluster.sh — commit, push, and remotely apply nixos-config to exo cluster nodes.
# Usage: ./scripts/deploy-cluster.sh [hostname...]
#   If no hostnames are given, deploys to all cluster nodes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_REMOTE="$(git -C "$REPO_DIR" remote get-url origin)"

CLUSTER_NODES=(
  "CK2Q9LN7PM-MBA"
  "C02FCCSWQ05D-MBP"
  "L75T4YHXV7-MBA"
  "GJHC5VVN49-MBP"
)

# If specific hosts passed as args, deploy only those
TARGETS=("${@:-${CLUSTER_NODES[@]}}")

# ── Resolve hostname → IP via ARP + SSH hostname probe ──────────────────────
# Builds a map of hostname→IP by SSHing to every LAN host that responds.
declare -A HOST_IP_MAP
resolve_cluster_ips() {
  echo "==> Scanning LAN for cluster nodes..."
  local subnet
  subnet=$(ipconfig getifaddr en0 2>/dev/null | sed 's/\.[0-9]*$/./')
  [ -z "$subnet" ] && subnet=$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | head -1 | sed 's/\.[0-9]*\/.*/./')

  # Ping sweep to populate ARP cache
  for i in $(seq 1 254); do
    ping -c1 -W1 "${subnet}${i}" &>/dev/null &
  done
  wait

  # Probe each ARP entry for SSH + hostname
  while IFS= read -r ip; do
    {
      h=$(ssh -o ConnectTimeout=3 -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              "casazza@$ip" hostname 2>/dev/null) || true
      if [ -n "$h" ]; then
        HOST_IP_MAP["$h"]="$ip"
        echo "    found $h @ $ip"
      fi
    } &
  done < <(arp -a 2>/dev/null \
    | grep "en0 ifscope" \
    | grep -v "ff:ff\|mcast\|224\.\|239\." \
    | awk '{print $2}' | tr -d '()')
  wait
}

resolve_cluster_ips

# ── 1. Commit & push ────────────────────────────────────────────────────────
cd "$REPO_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "==> Committing local changes..."
  git add -A
  git commit -m "chore: deploy cluster config $(date '+%Y-%m-%d %H:%M')"
fi
echo "==> Pushing to $REPO_REMOTE..."
git push

# ── 2. Deploy to each target ────────────────────────────────────────────────
FAILED=()
for host in "${TARGETS[@]}"; do
  ip="${HOST_IP_MAP[$host]:-}"
  echo ""

  if [ -z "$ip" ]; then
    echo "==> SKIP: $host — not found on LAN"
    FAILED+=("$host (not found)")
    continue
  fi

  echo "==> Deploying to $host ($ip)..."

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "casazza@$ip" true 2>/dev/null; then
    echo "  SKIP: $host unreachable"
    FAILED+=("$host (unreachable)")
    continue
  fi

  if ssh -o ConnectTimeout=30 "casazza@$ip" bash -s -- "$host" "$REPO_REMOTE" <<'REMOTE'
    set -euo pipefail
    HOSTNAME="$1"
    REPO_REMOTE="$2"
    REPO_DIR="$HOME/.config/nixos-config"

    if [ ! -d "$REPO_DIR/.git" ]; then
      echo "  Cloning repo..."
      git clone "$REPO_REMOTE" "$REPO_DIR"
    else
      echo "  Pulling latest..."
      git -C "$REPO_DIR" pull --ff-only
    fi

    echo "  Switching to config $HOSTNAME..."
    cd "$REPO_DIR"
    nh darwin switch ".#$HOSTNAME"
REMOTE
  then
    echo "  OK: $host"
  else
    echo "  FAILED: $host"
    FAILED+=("$host (activation failed)")
  fi
done

# ── 3. Summary ───────────────────────────────────────────────────────────────
echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "==> All nodes deployed successfully."
else
  echo "==> Done. Failed nodes:"
  for f in "${FAILED[@]}"; do echo "    - $f"; done
  exit 1
fi
