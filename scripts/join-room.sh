#!/bin/bash
# Join an Agent Arena room by invite code OR room ID (open rooms)
# Usage: bash join-room.sh <INVITE_CODE_OR_ROOM_ID>
# Detects format: UUID → roomId (open rooms), other → inviteCode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

INPUT="$1"

if [ -z "$INPUT" ]; then
  echo '{"error":"Usage: join-room.sh <INVITE_CODE_OR_ROOM_ID>"}'
  exit 1
fi

_ensure_token

# Detect if input is a UUID (roomId) or invite code
if _is_uuid "$INPUT"; then
  BODY=$(jq -n --arg roomId "$INPUT" '{roomId: $roomId}')
else
  BODY=$(jq -n --arg code "$INPUT" '{inviteCode: $code}')
fi

# Join room
JOIN_RESULT=$(curl -s --max-time 15 -X POST "$ARENA_BASE_URL/rooms/join" \
  -H "Authorization: Bearer $ARENA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")

ROOM_ID=$(echo "$JOIN_RESULT" | jq -r '.id // empty')

if [ -z "$ROOM_ID" ]; then
  echo '{"error":"Failed to join room","details":'"$JOIN_RESULT"'}'
  exit 1
fi

# Auto-ready if configured
AUTO_READY=$(jq -r '.autoReady // true' "$CONFIG_FILE" 2>/dev/null)
READY_STATUS="skipped"
if [ "$AUTO_READY" = "true" ]; then
  READY_RESULT=$(curl -s --max-time 15 -X POST "$ARENA_BASE_URL/rooms/$ROOM_ID/ready" \
    -H "Authorization: Bearer $ARENA_TOKEN")
  READY_STATUS=$(echo "$READY_RESULT" | jq -r '.status // "?"')
fi

# Get room details
ROOM_DETAILS=$(curl -s --max-time 15 "$ARENA_BASE_URL/rooms/$ROOM_ID" \
  -H "Authorization: Bearer $ARENA_TOKEN")

CRON_ID=$(jq -r '.cronId // empty' "$CONFIG_FILE" 2>/dev/null)

echo "$ROOM_DETAILS" | jq \
  --arg ready "$READY_STATUS" \
  --arg cronId "$CRON_ID" \
  '{
    roomId: (.id // ""),
    topic: (.topic // ""),
    joinMode: (.joinMode // "INVITE"),
    maxRounds: (.maxRounds // 0),
    maxAgents: (.maxAgents // 0),
    status: (.status // "unknown"),
    ready: $ready,
    participants: [(.participants // [])[] | .profile.name // ""],
    cronId: $cronId,
    action_required: (if $cronId != "" then "ENABLE_POLLING_CRON" else "CREATE_POLLING_CRON" end)
  }'
