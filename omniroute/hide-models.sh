#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

INPUT_FILE="${1:-$SCRIPT_DIR/models.json}"

# Load credentials exclusively from environment or local .env
if [ -f "$ENV_FILE" ]; then
  BASE_DOMAIN=$(sed -n 's/^BASE_DOMAIN=//p' "$ENV_FILE" | tr -d '\r\n"' || true)
  HOST_VAL=$(sed -n 's/^OMNIROUTE_HOST=//p' "$ENV_FILE" | tr -d '\r\n"' || true)
  RESOLVED_HOST=$(echo "$HOST_VAL" | sed "s/\${BASE_DOMAIN:?}/$BASE_DOMAIN/" | sed "s/\${BASE_DOMAIN}/$BASE_DOMAIN/")
  
  [ -n "$RESOLVED_HOST" ] && BASE_URL="${BASE_URL:-https://$RESOLVED_HOST}"
  API_KEY="${API_KEY:-$(sed -n 's/^OMNIROUTE_API_KEY=//p' "$ENV_FILE" | tr -d '\r\n"')}"
fi

: "${BASE_URL:?Error: BASE_URL is required (set in environment or .env)}"
: "${API_KEY:?Error: API_KEY is required (set OMNIROUTE_API_KEY in .env)}"

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: file '$INPUT_FILE' not found."
  exit 1
fi

echo "Hiding models from '$INPUT_FILE' on $BASE_URL..."

MODALITIES=("" "chat" "images" "videos" "video" "embeddings" "audio-speech")

jq -c '.[]' "$INPUT_FILE" | while read -r item; do
  PROVIDER=$(echo "$item" | jq -r '.provider')
  MODEL_IDS=$(echo "$item" | jq -c '.modelIds')

  echo "-> Hiding models for provider: $PROVIDER"
  for MOD in "${MODALITIES[@]}"; do
    if [ -z "$MOD" ]; then
      PAYLOAD="{\"modelIds\": $MODEL_IDS, \"isHidden\": true}"
    else
      PAYLOAD="{\"modelIds\": $MODEL_IDS, \"isHidden\": true, \"modality\": \"$MOD\"}"
    fi

    curl -s -X PATCH "$BASE_URL/api/provider-models?provider=$PROVIDER" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" > /dev/null
  done

  sleep 0.1
done

echo "Done. All models processed."
