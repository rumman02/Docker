# OmniRoute Model Management & Visibility Guide

> **Scope**: Reference and agent-friendly operational guide for managing, hiding, unhiding, and auditing AI models across providers on OmniRoute.

---

## 1. Core Endpoints & Architecture

| Purpose | Method & Path | Auth Required | Description |
| :--- | :--- | :--- | :--- |
| **Live Catalog** | `GET /v1/models` | Client / Manage Bearer Key | What AI clients see. Returns only active, unhidden models. |
| **Full Manifest** | `GET /api/v1/provider-plugin-manifest` | Management Bearer Key | Complete catalog of all 250+ providers and ~3,200 models supported by OmniRoute. |
| **Model Visibility** | `PATCH /api/provider-models?provider=<name>` | Management Bearer Key | Toggles model visibility (`"isHidden": true/false`) per provider. |
| **MCP Stream** | `POST/GET /api/mcp/stream` | Management Bearer Key (`mcp:connect`) | Streamable HTTP endpoint for MCP agents. Requires `Authorization: Bearer <key>`. |

---

## 2. Dynamic Model Hiding Architecture (`hide-models.sh`)

The script is **100% independent of any static files** on disk.

### Dynamic Pipeline
1. **Catalog Fetch:** Dynamically queries `GET /api/v1/provider-plugin-manifest` (retrieves all 250+ providers and 3,200+ models, including unconnected ones like Kiro, OpenAI, Anthropic).
2. **Live Models Fetch:** Dynamically queries `GET /v1/models` (retrieves any live community or dynamic Google One / Antigravity OAuth models).
3. **Auto-Merge Snapshot:** Merges both lists into an auto-cleaning temporary file (`mktemp`) pairing both bare and full IDs.
4. **Modality & Provider Execution:** Loops through all 251 providers sending universal (`"isHidden": true`) and modality-specific (`images`, `videos`, `embeddings`, `chat`) hide calls.
5. **Guaranteed Cleanup:** `trap 'rm -f ...' EXIT` deletes all temporary files automatically upon completion or interruption.

---

## 3. Automation Execution

### Run on Local Dev Instance
```bash
./hide-models.sh
```

### Run Against Remote Production Instance (from Mac over Tailscale)
```bash
BASE_URL="https://omniroute.production.domain" \
API_KEY="<PROD_API_KEY>" \
./hide-models.sh
```

### To Unhide Models (Revert)
Change `"isHidden": true` to `"isHidden": false` in the API payload:
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
  | jq '.providers[].models[] | select(.id | test("gemini"))'
```
