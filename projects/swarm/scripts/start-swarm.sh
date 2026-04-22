#!/usr/bin/env bash
# Boot the swarm stack on luna:
#   1. Phoenix (:6006)       - observability UI + OTLP ingest
#   2. LiteLLM proxy (:4000) - router over vLLM + exo + worker nodes
#
# vLLM itself is a systemd unit (modules/nixos/vllm) so we don't start it
# here — this script only brings up the orchestration layer.
#
# Ctrl-C tears everything down via the trap below.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p .run
PHOENIX_LOG=".run/phoenix.log"
LITELLM_LOG=".run/litellm.log"

pids=()
cleanup() {
  echo
  echo "swarm: shutting down ($$ pids: ${pids[*]:-})"
  for p in "${pids[@]:-}"; do
    kill "$p" 2> /dev/null || true
  done
  wait 2> /dev/null || true
}
trap cleanup EXIT INT TERM

echo "swarm: starting Phoenix → $PHOENIX_LOG"
./scripts/start-phoenix.sh > "$PHOENIX_LOG" 2>&1 &
pids+=($!)

# Wait for Phoenix's OTLP endpoint before booting LiteLLM so the very
# first router calls aren't dropped spans.
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null http://localhost:6006/; then break; fi
  sleep 1
done

echo "swarm: starting LiteLLM → $LITELLM_LOG"
./scripts/start-litellm.sh > "$LITELLM_LOG" 2>&1 &
pids+=($!)

for _ in $(seq 1 60); do
  if curl -sf -o /dev/null http://localhost:4000/health/liveliness; then break; fi
  sleep 1
done

echo
echo "swarm: ready"
echo "  Phoenix UI      http://localhost:6006"
echo "  LiteLLM proxy   http://localhost:4000"
echo '  Run a task:     uv run swarm run "your task"'
echo
echo "swarm: tailing logs (Ctrl-C to stop everything)"
tail -n +1 -F "$PHOENIX_LOG" "$LITELLM_LOG"
