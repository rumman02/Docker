# OmniRoute Model Management & Visibility Guide

> **Scope**: Reference and agent-friendly operational guide for managing, hiding, unhiding, and auditing AI models across providers on OmniRoute.

---

## 1. Core Endpoints & Architecture

| Purpose | Method & Path | Auth Required | Description |
| :--- | :--- | :--- | :--- |
| **Live Catalog** | `GET /v1/models` | Client / Manage Bearer Key | What AI clients (Cursor, Claude Code, Cline) see. Returns only active, unhidden models. |
| **Full Manifest** | `GET /api/v1/provider-plugin-manifest` | Management Bearer Key | Complete catalog of all 250+ providers and ~3,200 models supported by OmniRoute. |
| **Model Visibility** | `PATCH /api/provider-models?provider=<name>` | Management Bearer Key | Toggles model visibility (`"isHidden": true/false`) per provider. |
| **MCP Stream** | `POST/GET /api/mcp/stream` | Management Bearer Key (`mcp:connect`) | Streamable HTTP endpoint for MCP agents. Requires `Authorization: Bearer <key>`. |

---

## 2. Model Hiding Mechanism

Hiding is stored in OmniRoute's SQLite database (`/app/data/storage.sqlite`) in `key_value` under `namespace = 'modelCompatOverrides'`.

### API Payload Schema
```json
{
  "modelIds": ["model-id-1", "model-id-2"],
  "isHidden": true,
  "modality": "chat"
}
```

### Modality Rules
* **Universal Hiding:** Omit `"modality"` to hide completely across all endpoints.
* **Modality Specific:**
  * `"chat"`: Hides from `/v1/chat/completions`.
  * `"images"`: Hides from `/v1/images/*` (Required for **AI Horde** models).
  * `"videos"`: Hides from video endpoints (Required for **Veo / Seedance** models).
  * `"embeddings"`: Hides from `/v1/embeddings`.

### Model ID Naming Nuance
* **Standard Models (AI Horde, Chat):** Must use the **bare ID without prefix** (e.g. `AbsoluteReality`, not `aihorde/AbsoluteReality`).
* **Aliased Video Models (Veo):** When provider name (`veoaifree-web`) does not match model prefix (`veo-free/`), OmniRoute checks the **full prefixed ID** (`veo-free/veo`).
* **Best Practice:** Keep both bare ID and prefixed ID in `models.json` for guaranteed matching.

---

## 3. Automation Scripts & Files

### Files Overview
* `models.json`: All models grouped by provider (`{"provider": "...", "modelIds": [...]}`).
* `hide-models.sh`: Shell script that reads `models.json` and issues PATCH requests across all modalities. Zero secrets or URLs are hardcoded — it dynamically pulls `OMNIROUTE_API_KEY` and `OMNIROUTE_HOST` from `.env`.

### Execution Command
```bash
# Hide all models defined in models.json:
./hide-models.sh

# Or target a specific file:
./hide-models.sh custom-models.json
```

### To Unhide Models (Revert)
Change `"isHidden": true` to `"isHidden": false` in the API payload or run:
```bash
curl -s -X PATCH "$BASE_URL/api/provider-models?provider=<PROVIDER>" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"modelIds": ["<MODEL_ID>"], "isHidden": false}'
```

---

## 4. Agent Operational Runbook

### Environment Initialization
```bash
API_KEY=$(sed -n 's/^OMNIROUTE_API_KEY=//p' .env | tr -d '\r\n')
BASE_URL="https://$(sed -n 's/^OMNIROUTE_HOST=//p' .env | sed "s/\${BASE_DOMAIN:?}/$(sed -n 's/^BASE_DOMAIN=//p' .env)/" | tr -d '\r\n')"
```

### Check Status of Visible Models
```bash
curl -s -H "Authorization: Bearer $API_KEY" "$BASE_URL/v1/models" | jq '{total: (.data | length), models: [.data[].id]}'
```

### Check if a Specific Model Exists in OmniRoute's Built-in Catalog
```bash
curl -s -H "Authorization: Bearer $API_KEY" "$BASE_URL/api/v1/provider-plugin-manifest" \
  | jq '.providers[].models[] | select(.id | test("claude-sonnet-5"))'
```

### Hide a Newly Discovered Model Instantly
```bash
MODEL="new-model-id"
PROVIDER="provider-name"

for MOD in "" "chat" "images" "videos" "embeddings"; do
  [ -z "$MOD" ] && D="{\"modelIds\": [\"$MODEL\"], \"isHidden\": true}" || D="{\"modelIds\": [\"$MODEL\"], \"isHidden\": true, \"modality\": \"$MOD\"}"
  curl -s -X PATCH "$BASE_URL/api/provider-models?provider=$PROVIDER" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$D" > /dev/null
done
```

---

## 5. Safety & Edge Cases

1. **Hiding Non-Existent Models:** Completely safe. OmniRoute stores the ID in an array; non-existent IDs act as harmless no-ops.
2. **Community / Dynamic Providers (AI Horde):** AI Horde dynamically publishes models from active community workers. Newly spun-up community models may temporarily appear until added and hidden.
3. **Database Reset on Recreate:** If `compose.yaml` volume is ever wiped, `modelCompatOverrides` resets. Re-running `./hide-models.sh` restores the hidden state in ~60 seconds.
