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
ACCESS_TOKEN_FILE="$CONFIG_DIR/secrets/gcloud-access-token"
ID_TOKEN_FILE="$CONFIG_DIR/secrets/gcloud-id-token"
LOG_FILE="$HOME/.local/state/bifrost/token-refresh.log"
mkdir -p "$CONFIG_DIR/secrets" "$(dirname "$LOG_FILE")"
chmod 700 "$CONFIG_DIR/secrets"

ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

if ! command -v gcloud >/dev/null 2>&1; then
  echo "$(ts) gcloud not on PATH; cannot refresh tokens" >> "$LOG_FILE"
  exit 1
fi

# Atomic write so bifrost never reads a half-written token.
write_token() {
  local file="$1"
  local value="$2"
  local tmp="${file}.tmp.$$"
  printf '%s' "$value" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

# 1) ADC access token — for Vertex AI (Gemini). Requires
#    `gcloud auth application-default login` once. Used by bifrost's
#    native vertex provider via google.FindDefaultCredentials.
ACCESS_TOKEN="$(gcloud auth application-default print-access-token 2>>"$LOG_FILE" || true)"
if [ -n "$ACCESS_TOKEN" ]; then
  write_token "$ACCESS_TOKEN_FILE" "$ACCESS_TOKEN"
  echo "$(ts) refreshed access token (length=${#ACCESS_TOKEN})" >> "$LOG_FILE"
else
  echo "$(ts) failed to obtain access token (run: gcloud auth application-default login)" >> "$LOG_FILE"
fi

# 2) Identity token — for the Schrodinger Vertex CLI proxy
#    (vertex-proxy.sdgr.app). It validates a Google id-token (JWT), NOT
#    an access token. Returns 401/403 on access tokens. Sourced from
#    the user's gcloud login (different from ADC).
ID_TOKEN="$(gcloud auth print-identity-token 2>>"$LOG_FILE" || true)"
if [ -n "$ID_TOKEN" ]; then
  write_token "$ID_TOKEN_FILE" "$ID_TOKEN"
  echo "$(ts) refreshed id token (length=${#ID_TOKEN})" >> "$LOG_FILE"
else
  echo "$(ts) failed to obtain id token (run: gcloud auth login)" >> "$LOG_FILE"
fi

# Kick bifrost so it picks up the new tokens. Idempotent; if bifrost
# isn't running yet, this is a no-op that prints to stderr (silenced).
launchctl kickstart -k "gui/$(id -u)/ai.bifrost.gateway" 2>/dev/null || true
