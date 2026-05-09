#!/usr/bin/env bash
# refresh-gcloud-token.sh — refreshes the Google ADC access token + writes
# to a file that bifrost reads (via $GCLOUD_ACCESS_TOKEN env var indirection
# in the launchd plist), then kicks bifrost so it picks up the new token.
#
# Runs every ~50 minutes via launchd StartInterval (Google ADC tokens
# expire in 1h). On failure, leaves the previous token in place — bifrost
# keeps using the stale token until it 401s, at which point hopefully the
# next refresh has succeeded.
#
# Path conventions match modules/darwin/bifrost/default.nix.
set -euo pipefail

CONFIG_DIR="${1:-$HOME/.bifrost}"
TOKEN_FILE="$CONFIG_DIR/secrets/gcloud-access-token"
LOG_FILE="$HOME/.local/state/bifrost/token-refresh.log"
mkdir -p "$(dirname "$TOKEN_FILE")" "$(dirname "$LOG_FILE")"
chmod 700 "$(dirname "$TOKEN_FILE")"

ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

if ! command -v gcloud >/dev/null 2>&1; then
  echo "$(ts) gcloud not on PATH; cannot refresh ADC token" >> "$LOG_FILE"
  exit 1
fi

# `gcloud auth application-default print-access-token` reads
# ~/.config/gcloud/application_default_credentials.json (set up via
# `gcloud auth application-default login` once, manually). It refreshes
# the token using the stored refresh_token if expired.
TOKEN="$(gcloud auth application-default print-access-token 2>>"$LOG_FILE" || true)"

if [ -z "$TOKEN" ]; then
  echo "$(ts) failed to obtain access token (run: gcloud auth application-default login)" >> "$LOG_FILE"
  exit 1
fi

# Atomic write so bifrost never reads a half-written token.
TMP="${TOKEN_FILE}.tmp.$$"
printf '%s' "$TOKEN" > "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$TOKEN_FILE"

echo "$(ts) refreshed gcloud access token (length=${#TOKEN})" >> "$LOG_FILE"

# Kick bifrost so it picks up the new token. Idempotent; if bifrost isn't
# running yet, this is a no-op that prints to stderr (silenced).
launchctl kickstart -k "gui/$(id -u)/ai.bifrost.gateway" 2>/dev/null || true
