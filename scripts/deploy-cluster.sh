#!/usr/bin/env bash
# deploy-cluster.sh — commit, push via colmena, then activate on all nodes in parallel.
# Usage: ./scripts/deploy-cluster.sh [hostname...]
#   If no hostnames are given, deploys to all reachable cluster nodes.
#
# Requires: colmena, mprocs (nix run nixpkgs#mprocs), nh, ssh
set -euo pipefail

# When run as a Nix app the script lives in the store, not the repo.
# Fall back to $PWD (user must run from repo root) or accept REPO_DIR env override.
if [[ -n "${REPO_DIR:-}" ]]; then
  : # already set
elif git -C "$(dirname "$0")" rev-parse --show-toplevel &>/dev/null; then
  REPO_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
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

# ── 2. Colmena: build & push closures ───────────────────────────────────────
COLMENA_TARGETS=$(IFS=,; echo "${TARGETS[*]}")
echo "==> Colmena push to: $COLMENA_TARGETS"
nix run github:zhaofengli/colmena -- apply \
  --on "$COLMENA_TARGETS" \
  --no-substitute \
  push 2>&1

# ── 3. Activate on all nodes in parallel via mprocs ─────────────────────────
# Each node gets a per-process activation script written to a temp file.
# mprocs runs them all concurrently with a per-node output panel.
# Exit codes are captured via sentinel files for the summary.

echo ""
echo "==> Activating ${#TARGETS[@]} nodes in parallel..."

MPROCS_CMDS=()

for host in "${TARGETS[@]}"; do
  ip="${NODE_IPS[$host]:-}"
  status_file="$LOG_DIR/${host}.status"

  # Write a self-contained activation script for this node
  activate_script="$LOG_DIR/${host}.sh"
  cat > "$activate_script" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
STATUS_FILE="${status_file}"

_fail() { echo "FAILED" > "\$STATUS_FILE"; echo "  FAILED: $host: \$1" >&2; exit 1; }
_ok()   { echo "OK"     > "\$STATUS_FILE"; echo "  OK: $host"; }

$(if [ "$host" = "$LOCAL_HOSTNAME" ] || [ "$ip" = "localhost" ]; then
cat << 'LOCAL'
echo "==> $host (local)"
if nh darwin switch ".#${host}"; then
  _ok
else
  _fail "local activation failed"
fi
LOCAL
else
cat << REMOTE
echo "==> $host ($ip)"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "casazza@${ip}" true 2>/dev/null; then
  echo "SKIP" > "\$STATUS_FILE"
  echo "  SKIP: $host ($ip) unreachable"
  exit 0
fi

ssh "casazza@${ip}" bash -s << 'INNEREOF' || _fail "activation failed"
set -euo pipefail
system_profile="/nix/var/nix/profiles/system"
[ -L "\$system_profile" ] || { echo "ERROR: no system profile"; exit 1; }
echo "  Running activate..."
sudo "\$system_profile/activate" 2>&1 || true
echo "  Running activate-user..."
"\$system_profile/activate-user" 2>&1 || true
INNEREOF
_ok
REMOTE
fi)
SCRIPT
  chmod +x "$activate_script"

  # mprocs expects "name=command" pairs
  MPROCS_CMDS+=("$host=$activate_script")
done

# Run all activations in parallel with mprocs
# --no-docs: skip the key-binding help line  --hide-keymap: cleaner output
mprocs --no-docs "${MPROCS_CMDS[@]}"

# ── 4. Summary ───────────────────────────────────────────────────────────────
echo ""
FAILED=()
SKIPPED=()
for host in "${TARGETS[@]}"; do
  status_file="$LOG_DIR/${host}.status"
  status="$(cat "$status_file" 2>/dev/null || echo "UNKNOWN")"
  case "$status" in
    OK)      echo "  [OK]   $host" ;;
    SKIP)    echo "  [SKIP] $host (unreachable)"; SKIPPED+=("$host") ;;
    FAILED)  echo "  [FAIL] $host"; FAILED+=("$host") ;;
    UNKNOWN) echo "  [???]  $host (no status written)"; FAILED+=("$host") ;;
  esac
done

echo ""
[ ${#SKIPPED[@]} -gt 0 ] && echo "==> Skipped (unreachable): ${SKIPPED[*]}"
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "==> All reachable nodes deployed and activated."
else
  echo "==> Failed nodes: ${FAILED[*]}"
  exit 1
fi
