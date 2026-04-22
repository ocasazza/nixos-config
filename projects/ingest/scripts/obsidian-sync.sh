#!/usr/bin/env bash
# One-shot Obsidian pull — invoked by `systemd.services.ingest-obsidian-*`.
#
# Thin wrapper; all logic lives in `ingest run-once obsidian` so you can
# reproduce exactly what the timer does from any dev shell.

set -euo pipefail

VENV="${INGEST_VENV:-/var/lib/ingest/venv}"
if [ ! -x "$VENV/bin/ingest" ]; then
	echo "ingest: venv not bootstrapped at $VENV — has the service started yet?" >&2
	exit 2
fi

exec "$VENV/bin/ingest" run-once obsidian
