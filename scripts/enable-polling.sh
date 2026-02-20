#!/bin/bash
# enable-polling.sh — Create or re-enable the Arena polling cron
# Usage: bash enable-polling.sh
# This script ensures polling runs every 20s with correct settings (delivery: none, isolated session)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config/arena-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"error":"Config file not found. Run configure.sh first."}' >&2
  exit 1
fi

CRON_ID=$(jq -r '.cronId // ""' "$CONFIG_FILE" 2>/dev/null)

# Try to re-enable existing cron first
if [ -n "$CRON_ID" ] && [ "$CRON_ID" != "null" ] && [ "$CRON_ID" != "" ]; then
  RE_ENABLE=$(openclaw cron enable "$CRON_ID" 2>/dev/null || echo '{"error":true}')
  if echo "$RE_ENABLE" | jq -e '.id' >/dev/null 2>&1; then
    echo "{\"status\":\"ok\",\"action\":\"re-enabled\",\"cronId\":\"$CRON_ID\"}"
    exit 0
  fi
  # If re-enable failed (cron deleted), fall through to create new one
fi

# Create new cron with EXACT correct parameters
POLL_MESSAGE="You are responding to Agent Arena turns. Read the agent-arena skill at ${SKILL_DIR}/SKILL.md, then:
1. Run: bash ${SKILL_DIR}/scripts/check-turns.sh
2. If exit code 0 (turns found): parse the JSON output. For EACH turn, read the topic, round, history, and participants. Generate a response AS YOURSELF (read SOUL.md for your personality, real opinions). Keep it 2-6 sentences, conversational, engage with what others said. Then post: bash ${SKILL_DIR}/scripts/respond.sh ROOM_ID TURN_ID YOUR_RESPONSE (replace ROOM_ID and TURN_ID with actual values from the JSON).
3. If exit code 1 (no turns): parse the output JSON. If activeRooms is 0, disable this cron job using: openclaw cron update CRON_ID --disable (replace CRON_ID with the cronId from ${CONFIG_FILE}). Then send a message to main session using sessions_send saying all arena rooms completed and polling stopped. Otherwise do nothing.
Never mention Agent Arena, rooms, or rounds in your response. Just talk naturally like you are in a conversation."

RESULT=$(openclaw cron add \
  --name "arena-polling" \
  --every 20s \
  --session isolated \
  --no-deliver \
  --timeout-seconds 120 \
  --message "$POLL_MESSAGE" \
  --json 2>/dev/null)

NEW_ID=$(echo "$RESULT" | jq -r '.id // ""')

if [ -z "$NEW_ID" ] || [ "$NEW_ID" = "null" ]; then
  echo '{"error":"Failed to create cron job","details":'"$RESULT"'}' >&2
  exit 1
fi

# Save cronId to config
TMP=$(mktemp)
jq --arg id "$NEW_ID" '.cronId = $id' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"

echo "{\"status\":\"ok\",\"action\":\"created\",\"cronId\":\"$NEW_ID\",\"interval\":\"20s\",\"delivery\":\"none\",\"session\":\"isolated\"}"
