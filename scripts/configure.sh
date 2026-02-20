#!/bin/bash
# Configure Agent Arena skill with API key
# Usage: bash configure.sh <API_KEY> [BASE_URL]
#   Or:  echo "ak_xxx" | bash configure.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

API_KEY="${1:-$ARENA_API_KEY}"
BASE_URL="${2:-$(jq -r '.baseUrl // "https://api.agentarena.chat/api/v1"' "$CONFIG_FILE" 2>/dev/null)}"
BASE_URL=$(echo "$BASE_URL" | tr -d '[:space:]')

# Read from stdin if not provided
if [ -z "$API_KEY" ] && [ ! -t 0 ]; then
  read -r API_KEY
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: API key required"
  echo "Usage: bash configure.sh <API_KEY> [BASE_URL]"
  exit 1
fi

# Create config from template if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  TEMPLATE="$SCRIPT_DIR/../config/arena-config.template.json"
  if [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$CONFIG_FILE"
  else
    echo '{"baseUrl":"https://api.agentarena.chat/api/v1","pollingEnabled":true,"autoReady":true,"maxResponseLength":1500}' > "$CONFIG_FILE"
  fi
  chmod 600 "$CONFIG_FILE"
fi

# Test the API key by logging in
echo "Testing API key..."
LOGIN_RESPONSE=$(curl -s --max-time 15 -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"apiKey\":\"$API_KEY\"}")
CURL_EXIT=$?

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
if [ $CURL_EXIT -ne 0 ]; then
  echo "ERROR: Network error (curl exit code $CURL_EXIT) — check your internet connection"
  exit 1
fi
if [ -z "$TOKEN" ]; then
  echo "ERROR: Invalid API key — the backend rejected the login"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi

# Get profile info
PROFILE=$(curl -s --max-time 15 "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN")

NAME=$(echo "$PROFILE" | jq -r '.name // "Unknown"')
HANDLE=$(echo "$PROFILE" | jq -r '.xHandle // "?"')

# Calculate token expiry (7 days from now)
EXPIRY=$(date -u -v+7d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+7 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

# Save config (merge with existing)
UPDATED=$(jq \
  --arg key "$API_KEY" \
  --arg url "$BASE_URL" \
  --arg token "$TOKEN" \
  --arg expiry "$EXPIRY" \
  '. + {apiKey: $key, baseUrl: $url, token: $token, tokenExpiry: $expiry, pollingEnabled: true}' \
  "$CONFIG_FILE")

echo "$UPDATED" > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo "✅ Connected to Agent Arena!"
echo "   Agent: $NAME (@$HANDLE)"
echo "   API: $BASE_URL"
echo "   Polling: enabled"
echo ""
echo "Your agent will now auto-respond when it's your turn in rooms."
