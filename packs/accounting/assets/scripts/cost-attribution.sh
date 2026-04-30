#!/usr/bin/env bash
# Per-agent cost attribution from claude-code JSONLs.
#
# Joins `gc session list --json` against ~/.claude/projects/<slug>/<sid>.jsonl
# for every gc session whose Provider is "claude-code", and emits a JSON
# array of {agent, gc_session_id, claude_session_id, model, in_tokens,
# out_tokens, cache_read, cache_create, est_usd_opus} records.
#
# For Provider=opencode sessions, claude-code JSONLs do not exist —
# cost lives in LiteLLM's spend tracking. This script flags those as
# unmeasurable here and points to the LiteLLM tally script (TODO).
#
# Usage:
#   cost-attribution.sh                 # all sessions, current city
#   cost-attribution.sh --since 24h     # last 24h only (TODO)

set -euo pipefail

CLAUDE_PROJECTS="${CLAUDE_PROJECTS:-$HOME/.claude/projects}"

# Opus 4 pricing as of 2026-04 (USD per 1M tokens). Used as worst-case
# upper bound; real cost depends on the model the session actually used.
PRICE_INPUT=15.00
PRICE_OUTPUT=75.00
PRICE_CACHE_R=1.50
PRICE_CACHE_W=18.75

# WorkDir → claude-code project slug: `/` → `-`, leading `-` preserved.
workdir_to_slug() { printf '%s' "$1" | sed 's|/|-|g'; }

gc session list --json | jq -c '.[] | {ID, Template, Provider, WorkDir}' \
| while IFS= read -r sess; do
    provider=$(jq -r '.Provider' <<<"$sess")
    workdir=$(jq -r '.WorkDir' <<<"$sess")
    agent=$(jq -r '.Template' <<<"$sess")
    gcid=$(jq -r '.ID' <<<"$sess")

    if [ "$provider" != "claude-code" ]; then
        jq -n --arg agent "$agent" --arg gcid "$gcid" --arg provider "$provider" \
          '{agent: $agent, gc_session_id: $gcid, provider: $provider,
            note: "cost lives in LiteLLM spend tracker, not claude-code JSONLs"}'
        continue
    fi

    slug=$(workdir_to_slug "$workdir")
    proj="$CLAUDE_PROJECTS/$slug"
    if [ ! -d "$proj" ]; then
        jq -n --arg agent "$agent" --arg gcid "$gcid" --arg slug "$slug" \
          '{agent: $agent, gc_session_id: $gcid, error: "no claude project dir", expected: $slug}'
        continue
    fi

    # Newest jsonl in the project dir is the live session for this agent.
    jsonl=$(ls -t "$proj"/*.jsonl 2>/dev/null | head -1 || true)
    if [ -z "$jsonl" ]; then
        jq -n --arg agent "$agent" --arg gcid "$gcid" \
          '{agent: $agent, gc_session_id: $gcid, error: "no jsonls in project dir"}'
        continue
    fi

    cid=$(basename "$jsonl" .jsonl)
    jq -s --arg agent "$agent" --arg gcid "$gcid" --arg cid "$cid" \
        --argjson pi "$PRICE_INPUT" --argjson po "$PRICE_OUTPUT" \
        --argjson pcr "$PRICE_CACHE_R" --argjson pcw "$PRICE_CACHE_W" '
      [.[] | select(.type=="assistant" and (.message.model // "") != "<synthetic>") | .message.usage]
      | { in: ([.[].input_tokens // 0] | add),
          out: ([.[].output_tokens // 0] | add),
          cr: ([.[].cache_read_input_tokens // 0] | add),
          cw: ([.[].cache_creation_input_tokens // 0] | add) }
      | { agent: $agent, gc_session_id: $gcid, claude_session_id: $cid,
          in_tokens: .in, out_tokens: .out, cache_read: .cr, cache_create: .cw,
          est_usd_opus: ((.in * $pi + .out * $po + .cr * $pcr + .cw * $pcw) / 1000000) }
    ' "$jsonl"
done | jq -cs 'sort_by(.est_usd_opus // 0) | reverse | .[]'
