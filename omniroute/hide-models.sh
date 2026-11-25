#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

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

# Create temporary files with guaranteed auto-cleanup
LIVE_TMP=$(mktemp "$SCRIPT_DIR/.live_tmp_XXXXXX.json")
MANIFEST_TMP=$(mktemp "$SCRIPT_DIR/.manifest_tmp_XXXXXX.json")
MODELS_TMP=$(mktemp "$SCRIPT_DIR/.models_tmp_XXXXXX.json")
trap 'rm -f "$LIVE_TMP" "$MANIFEST_TMP" "$MODELS_TMP"' EXIT INT TERM

echo "1. Dynamically fetching full provider catalog from $BASE_URL/api/v1/provider-plugin-manifest..."
curl -s -f -H "Authorization: Bearer $API_KEY" "$BASE_URL/api/v1/provider-plugin-manifest" > "$MANIFEST_TMP"

echo "2. Dynamically fetching live active models from $BASE_URL/v1/models..."
curl -s -f -H "Authorization: Bearer $API_KEY" "$BASE_URL/v1/models" > "$LIVE_TMP"

echo "3. Merging all provider models into dynamic snapshot..."
jq -s '
  # Extract all catalog models from manifest
  ([.[0].providers[]? | {provider: .id, ids: [.models[]?.id]}] | map(select((.ids | length) > 0))) as $manifest |
  
  # Extract live active models (pairing bare and prefixed IDs)
  ([.[1].data[]? | {provider: .owned_by, id: .id, bareId: (.id | sub("^[^/]+/"; ""))}]) as $live |
  
  # Combine, group by provider, and deduplicate
  ($manifest + [
    $live[] | {provider: .provider, ids: [.id, .bareId]}
  ])
  | group_by(.provider)
  | map({
      provider: .[0].provider,
      modelIds: ([.[].ids[]] | unique)
    })
' "$MANIFEST_TMP" "$LIVE_TMP" > "$MODELS_TMP"

TOTAL_PROVIDERS=$(jq 'length' "$MODELS_TMP")
TOTAL_MODELS=$(jq '[.[].modelIds | length] | add' "$MODELS_TMP")
echo "Compiled dynamic snapshot: $TOTAL_MODELS models across $TOTAL_PROVIDERS providers."

# Execute hiding across providers and modalities
MODALITIES=("" "chat" "images" "videos" "video" "embeddings" "audio-speech")

jq -c '.[]' "$MODELS_TMP" | while read -r item; do
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

echo "Done. All models hidden and temporary files automatically cleaned up."
