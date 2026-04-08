#!/usr/bin/env bash
# deploy-cluster.sh — build closures, copy via nix copy, activate via clush.
# All remote traffic goes over Thunderbolt Bridge (*.tb hostnames → 10.99.0.0/24).
#
# Requires: clush (pip3 install clustershell)
#
# Usage: nix run .#deploy-cluster [hostname...]
#   If no hostnames given, deploys to all cluster nodes.
set -euo pipefail

# ClusterShell is broken in nixpkgs — pick it up from pip install location.
for p in "$HOME/Library/Python/3.9/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  [[ -d $p ]] && export PATH="$p:$PATH"
done
if ! command -v clush &> /dev/null; then
  echo "error: clush not found. Install it: pip3 install clustershell" >&2
  exit 1
fi

# ── Repo root ─────────────────────────────────────────────────────────────────
if [[ -n ${REPO_DIR:-} ]]; then
  : # already set
elif git -C "$PWD" rev-parse --show-toplevel &> /dev/null; then
  REPO_DIR="$(git -C "$PWD" rev-parse --show-toplevel)"
else
  echo "error: cannot find nixos-config repo. Run from the repo root or set REPO_DIR." >&2
  exit 1
fi

LOCAL_HOSTNAME="$(hostname -s)"
SSH_USER="casazza"

# ── Cluster membership (must match thunderboltLinks in flake.nix) ─────────────
CLUSTER_NODES=(
  "CK2Q9LN7PM-MBA"
  "GJHC5VVN49-MBP"
  "GN9CFLM92K-MBP"
)

# TB hostname is just <hostname>.tb — resolved via /etc/hosts set by Nix.
tb_host() { echo "${1}.tb"; }

TARGETS=("${@:-${CLUSTER_NODES[@]}}")
LOG_DIR="$(mktemp -d /tmp/deploy-cluster.XXXXXX)"
trap 'rm -rf "$LOG_DIR"' EXIT

# Split into local vs remote
REMOTE_NODES=()
for host in "${TARGETS[@]}"; do
  [[ $host == "$LOCAL_HOSTNAME" ]] && continue
  REMOTE_NODES+=("$host")
done

# ── 1. Commit & push ─────────────────────────────────────────────────────────
cd "$REPO_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "==> Committing local changes..."
  git add -A
  git commit -m "chore: deploy cluster config $(date '+%Y-%m-%d %H:%M')"
fi
echo "==> Pushing..."
git push

# ── 2. Build all closures (Nix max-jobs handles parallelism) ──────────────────
echo "==> Building closures for: ${TARGETS[*]}"
BUILD_ATTRS=()
for host in "${TARGETS[@]}"; do
  BUILD_ATTRS+=(".#darwinConfigurations.${host}.system")
done
nix build --no-link "${BUILD_ATTRS[@]}"

# ── 3. Copy closures to remote nodes over TB in parallel ─────────────────────
if [[ ${#REMOTE_NODES[@]} -gt 0 ]]; then
  echo "==> Copying closures to remote nodes over Thunderbolt..."
  COPY_PIDS=()
  for host in "${REMOTE_NODES[@]}"; do
    tb="$(tb_host "$host")"
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SSH_USER}@${tb}" true &> /dev/null; then
      echo "  SKIP (unreachable over TB): $host"
      continue
    fi
    closure="$(nix path-info ".#darwinConfigurations.${host}.system")"
    echo "  copying ${host} → ${tb} ..."
    nix copy --no-check-sigs --to "ssh-ng://${SSH_USER}@${tb}" "$closure" \
      > "$LOG_DIR/${host}.copy.log" 2>&1 &
    COPY_PIDS+=($!)
  done
  for pid in "${COPY_PIDS[@]}"; do wait "$pid"; done
fi

# ── 4. Activate ──────────────────────────────────────────────────────────────

# Local activation (if this host is a target)
for host in "${TARGETS[@]}"; do
  if [[ $host == "$LOCAL_HOSTNAME" ]]; then
    echo "==> Activating $host (local)..."
    closure="$(nix path-info ".#darwinConfigurations.${host}.system")"
    sudo "${closure}/sw/bin/darwin-rebuild" activate 2>&1 | tee "$LOG_DIR/${host}.log"
    echo "OK" > "$LOG_DIR/${host}.status"
    break
  fi
done

# Remote activation via clush (parallel over TB)
if [[ ${#REMOTE_NODES[@]} -gt 0 ]]; then
  # Build comma-separated TB node list for clush -w
  TB_NODELIST=""
  for host in "${REMOTE_NODES[@]}"; do
    [[ -n $TB_NODELIST ]] && TB_NODELIST+=","
    TB_NODELIST+="$(tb_host "$host")"
  done

  echo "==> Activating remote nodes via clush: ${TB_NODELIST}"

  # Each remote node activates its own closure.
  # We build a per-host command map and feed it via --worker=ssh.
  for host in "${REMOTE_NODES[@]}"; do
    tb="$(tb_host "$host")"
    closure="$(nix path-info ".#darwinConfigurations.${host}.system" 2> /dev/null || echo "")"
    if [[ -z $closure ]]; then
      echo "  SKIP (no closure): $host"
      echo "SKIP" > "$LOG_DIR/${host}.status"
      continue
    fi
    echo "  → $host ($tb): $closure"
    # Write per-node activation script
    cat > "$LOG_DIR/${host}.activate.sh" << EOF
set -euo pipefail
[ -e "${closure}" ] || { echo "closure not found"; exit 1; }
sudo "${closure}/activate"
"${closure}/activate-user"
EOF
  done

  # clush over all remote TB nodes — each runs the same activate pattern
  # Since each node has a different closure path, we use clush --diff to
  # see divergent output, and run per-node via a loop with clush -w single.
  ACTIVATE_PIDS=()
  for host in "${REMOTE_NODES[@]}"; do
    tb="$(tb_host "$host")"
    [[ -f "$LOG_DIR/${host}.activate.sh" ]] || continue
    (
      if clush -w "$tb" -l "$SSH_USER" \
        -o "-o ConnectTimeout=5 -o BatchMode=yes" \
        -b < "$LOG_DIR/${host}.activate.sh" \
        > "$LOG_DIR/${host}.log" 2>&1; then
        echo "OK" > "$LOG_DIR/${host}.status"
      else
        echo "FAILED" > "$LOG_DIR/${host}.status"
      fi
    ) &
    ACTIVATE_PIDS+=($!)
  done
  for pid in "${ACTIVATE_PIDS[@]}"; do wait "$pid"; done
fi

# ── 5. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "==> Deploy summary:"
FAILED=()
SKIPPED=()
for host in "${TARGETS[@]}"; do
  status="$(cat "$LOG_DIR/${host}.status" 2> /dev/null || echo "UNKNOWN")"
  case "$status" in
  OK) echo "  [OK]   $host" ;;
  SKIP)
    echo "  [SKIP] $host (unreachable)"
    SKIPPED+=("$host")
    ;;
  FAILED)
    echo "  [FAIL] $host (see $LOG_DIR/${host}.log)"
    FAILED+=("$host")
    ;;
  UNKNOWN)
    echo "  [???]  $host"
    FAILED+=("$host")
    ;;
  esac
done

echo ""
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "==> Skipped: ${SKIPPED[*]}"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "==> All reachable nodes deployed and activated over Thunderbolt."
else
  echo "==> Failed: ${FAILED[*]}"
  exit 1
fi
