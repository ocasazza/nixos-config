#!/usr/bin/env bash
# One-shot Atlassian pull — invoked by `systemd.services.ingest-atlassian-*`.
#
# The NixOS unit sets INGEST_* env vars and runs this script. The script
# is intentionally thin — all logic lives in the Python CLI so you can
# reproduce a run from any dev shell with `ingest run-once atlassian`.

set -euo pipefail

VENV="${INGEST_VENV:-/var/lib/ingest/venv}"
if [ ! -x "$VENV/bin/ingest" ]; then
	echo "ingest: venv not bootstrapped at $VENV — has the service started yet?" >&2
	exit 2
fi

exec "$VENV/bin/ingest" run-once atlassian
