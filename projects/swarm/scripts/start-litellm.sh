#!/usr/bin/env bash
# Start the LiteLLM proxy in front of vLLM (:8000) and exo (:52416).
# Reads projects/swarm/litellm_config.yaml — edit that to add backends.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${LITELLM_PORT:=4000}"
: "${PHOENIX_COLLECTOR_ENDPOINT:=http://localhost:6006/v1/traces}"

# ── 10G NIC binding ───────────────────────────────────────────────────
# luna has two physical NICs:
#   * enp0s31f6 — onboard Intel i219-LM (1 GbE, default gateway, WiFi/LAN)
#   * enp3s0    — Aquantia AQC113 (10 GbE, dedicated high-throughput lane)
#
# LiteLLM binds to the 10G interface's IPv4 so vLLM's tensor-parallel
# traffic and cross-host exo federation don't contend with WiFi / the
# mgmt plane. The iface name is hardcoded here (luna-specific); when
# LiteLLM gets promoted to a systemd unit (see TODO in litellm_config.yaml)
# the binding will move to a NixOS module that reads the IP from
# `config.networking.interfaces.<iface>.ipv4.addresses` declaratively.
#
# If the 10G link is down (cable unplugged, switch off), fall back to
# 0.0.0.0 so the proxy still starts — better than hanging on `litellm
# --host ''` at boot.
LITELLM_IFACE="${LITELLM_IFACE:-enp3s0}"
LITELLM_HOST="$(ip -4 -br addr show dev "$LITELLM_IFACE" 2>/dev/null \
  | awk '{print $3}' | cut -d/ -f1)"

if [ -z "${LITELLM_HOST:-}" ]; then
  echo "start-litellm: WARNING — $LITELLM_IFACE has no IPv4 address" \
       "(link down?). Falling back to 0.0.0.0." >&2
  LITELLM_HOST="0.0.0.0"
fi

# Forward OTLP spans from LiteLLM into Phoenix so model-router decisions
# (which backend served which request) show up in the swarm trace tree.
export OTEL_EXPORTER_OTLP_ENDPOINT="$PHOENIX_COLLECTOR_ENDPOINT"
export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"

exec uv run --project . litellm \
  --config ./litellm_config.yaml \
  --port "$LITELLM_PORT" \
  --host "$LITELLM_HOST"
