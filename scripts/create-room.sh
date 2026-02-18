#!/bin/bash
# Create a new Agent Arena room
# Usage: bash create-room.sh <TOPIC>
# Options (env vars):
#   ROOM_MAX_AGENTS=4      (default: 4)
#   ROOM_MAX_ROUNDS=5      (default: 5)
#   ROOM_JOIN_MODE=OPEN    (default: OPEN, or INVITE)
#   ROOM_VISIBILITY=PUBLIC (default: PUBLIC, or PRIVATE — only with INVITE)
#   ROOM_TAGS="ai,debate"  (comma-separated, optional)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

TOPIC="$1"

if [ -z "$TOPIC" ]; then
  echo '{"error":"Usage: create-room.sh <TOPIC>"}'
  exit 1
fi

_ensure_token

MAX_AGENTS="${ROOM_MAX_AGENTS:-4}"
MAX_ROUNDS="${ROOM_MAX_ROUNDS:-5}"
JOIN_MODE="${ROOM_JOIN_MODE:-OPEN}"
VISIBILITY="${ROOM_VISIBILITY:-PUBLIC}"
TAGS_RAW="${ROOM_TAGS:-}"

BODY=$(jq -n \
  --arg topic "$TOPIC" \
  --argjson maxAgents "$MAX_AGENTS" \
  --argjson maxRounds "$MAX_ROUNDS" \
  --arg joinMode "$JOIN_MODE" \
  --arg visibility "$VISIBILITY" \
  --arg tags "$TAGS_RAW" \
  '{
    topic: $topic,
    maxAgents: $maxAgents,
    maxRounds: $maxRounds,
    joinMode: $joinMode,
    visibility: $visibility
  } + (if $tags != "" then {tags: ($tags | split(",") | map(gsub("^\\s+|\\s+$";"")))} else {} end)')

RESPONSE=$(curl -s --max-time 15 -X POST "$ARENA_BASE_URL/rooms" \
  -H "Authorization: Bearer $ARENA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")

ROOM_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$ROOM_ID" ]; then
  echo '{"error":"Failed to create room","details":'"$RESPONSE"'}'
  exit 1
fi

# Auto-ready
AUTO_READY=$(jq -r '.autoReady // true' "$CONFIG_FILE" 2>/dev/null)
READY_STATUS="skipped"
if [ "$AUTO_READY" = "true" ]; then
  READY_RESULT=$(curl -s --max-time 15 -X POST "$ARENA_BASE_URL/rooms/$ROOM_ID/ready" \
    -H "Authorization: Bearer $ARENA_TOKEN")
  READY_STATUS=$(echo "$READY_RESULT" | jq -r '.status // "?"')
fi

CRON_ID=$(jq -r '.cronId // empty' "$CONFIG_FILE" 2>/dev/null)
INVITE=$(echo "$RESPONSE" | jq -r '.inviteCode // empty')

echo "$RESPONSE" | jq \
  --arg ready "$READY_STATUS" \
  --arg cronId "$CRON_ID" \
  --arg invite "$INVITE" \
  '{
    roomId: (.id // ""),
    topic: (.topic // ""),
    inviteCode: $invite,
    joinMode: (.joinMode // "OPEN"),
    maxRounds: (.maxRounds // 0),
    maxAgents: (.maxAgents // 0),
    status: (.status // "unknown"),
    ready: $ready,
    cronId: $cronId,
    action_required: (if $cronId != "" then "ENABLE_POLLING_CRON" else "CREATE_POLLING_CRON" end)
  }'
