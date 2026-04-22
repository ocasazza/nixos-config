#!/usr/bin/env bash
# One-shot GitHub pull — invoked by `systemd.services.ingest-github-*`.

set -euo pipefail

VENV="${INGEST_VENV:-/var/lib/ingest/venv}"
if [ ! -x "$VENV/bin/ingest" ]; then
	echo "ingest: venv not bootstrapped at $VENV" >&2
	exit 2
fi

exec "$VENV/bin/ingest" run-once github
