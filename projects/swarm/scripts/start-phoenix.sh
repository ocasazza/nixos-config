#!/usr/bin/env bash
# Start Arize Phoenix's OTLP collector + live UI.
#   UI:  http://localhost:6006
#   OTLP ingest: http://localhost:6006/v1/traces
set -euo pipefail

cd "$(dirname "$0")/.."

: "${PHOENIX_HOST:=0.0.0.0}"
: "${PHOENIX_PORT:=6006}"
# Phoenix also binds an OTLP gRPC listener; default 4317 collides with
# luna's existing `otelcol-contrib`. 4318 is the OTLP/HTTP default and
# also in wide use, so we pick 4319 to stay clear of both.
: "${PHOENIX_GRPC_PORT:=4319}"

# Bind on 0.0.0.0 so worker nodes across the LAN can also post spans here.
export PHOENIX_HOST PHOENIX_PORT PHOENIX_GRPC_PORT
export PHOENIX_WORKING_DIR="${PHOENIX_WORKING_DIR:-$HOME/.phoenix}"

exec uv run --project . phoenix serve
