# Bring-up checklist

Order matters; verify each step before moving on. Base dir: `~/docker-local`.

## 0. Env files — self-contained per stack
```bash
cd ~/docker-local
DK="$(sed -n 's/^DK=//p' ./.env 2>/dev/null)"   # engine CLI name — value lives in root .env (gitignored)
DK="${DK:-docker}"
kcs() { "$DK" compose "$@"; }
```
Each stack owns a self-contained `.env` (its secrets/tokens; comment headers per AGENTS.md §1.3; `BASE_DOMAIN` and shared runtime key `TZ` are edited once in root `.env.global` and applied by `./sync-env` only to stacks whose compose.yaml/.env consume them; consumed-only aliases stay local — n8n `GENERIC_TIMEZONE=${TZ:?}`, network `DNS_DOMAIN=${BASE_DOMAIN:?}`). Below: from the stack dir, `kcs <cmd>`; bare engine commands as `"$DK" <cmd>`. Agents: shell functions don't persist across tool calls — don't paste step 0; resolve `DK` per call: `DK="$(sed -n 's/^DK=//p' ~/docker-local/.env 2>/dev/null)"; DK="${DK:-docker}"`.

## 1. net_anchor — owns the shared bridge networks (up first, everything joins these)
```bash
cd ~/docker-local/net_anchor && kcs up -d
"$DK" network ls   # all thirteen: traefik_net, openwa_net, openclaw_net, omniroute_net, browseforge_net, postiz_net, postgres_net, redis_net, temporal_net, nginx_net, camofox_net, tailscale_net, network_socket_net
"$DK" ps -f name=net_anchor --format '{{.Names}}: {{.Status}}'   # net_anchor up
```
First `up` is chatty — one "network with name … was not created for project" warning per network = expected adoption noise.

## 2. network — edge path: traefik, tailscale, cloudflared, coredns
```bash
cd ../network && kcs up -d
"$DK" ps --format '{{.Names}}: {{.Status}}'   # traefik healthy; tailscale healthy; cloudflared up (only after traefik healthy); coredns up
"$DK" logs network_traefik 2>&1 | grep -m1 "Failed to retrieve information of the docker client"   # must print NOTHING — if it prints, set SOCKET_PROXY_USER per HOSTS.md (engine socket group membership)
dig @${TAILSCALE_IP} soa ${DNS_DOMAIN} +short   # from the Mac; needs dig (brew install bind) — answers from the zone file
```
Confirm the Let's Encrypt certs arrived (catches the 502 before it happens):
```bash
"$DK" logs --since 5m network_traefik 2>&1 | grep -iE "unable to obtain|ACME.*error"   # must print NOTHING. "Unable to obtain ACME certificate ... could not find zone" = DNS not settled -> wait a minute, kcs restart traefik, re-check
"$DK" logs network_traefik 2>&1 | grep -i "failed to verify certificate"   # cloudflared-side twin check; must also be empty
```

## 3. tailscale status
```bash
"$DK" exec network_tailscale tailscale status   # connected
```

## 4. database
```bash
cd ../database && kcs up -d
"$DK" ps -f name=postgres -f name=redis --format '{{.Names}}: {{.Status}}'   # both healthy
```
Redis DBs (database/README.md): 0 openwa queue, 1 openwa cache, 2 omniroute, 3 postiz, 4 searxng (reserved, stack removed), 5 n8n_wa_dedupe. Per-service PG provisioning: `database/postgres/.env.services`. postiz DB: user `postiz_user`, db `postiz` (hand-provisioned 2026-10-20 — volume predates the entry).

## 5. n8n
```bash
cd ../n8n && kcs up -d
"$DK" ps -f name=n8n --format '{{.Names}}: {{.Status}}'   # healthy
"$DK" logs --tail 3 n8n 2>&1 | grep "Editor is now accessible"
```

## 6. browseforge
```bash
cd ~/docker-local/browseforge && kcs up -d
"$DK" ps -f name=browseforge --format '{{.Names}}: {{.Status}}'   # healthy after start_period 120s
"$DK" logs --tail 5 browseforge   # first boot seeds browsers — watch this, not health, for minutes
"$DK" exec browseforge /app/BrowseForge token   # API/MCP/Playwright bearer token (after boot)
```
Public check (external, like the n8n one below): https://browseforge.example.com — needs the hostname routed in the Cloudflare tunnel ingress + a DNS record first; per README Gotcha 3, don't assume the dashboard UI is login-gated.
Since 2026-11-07 n8n no longer starts/stops BrowseForge (socket proxy stack gone); it simply stays up.
Historical note — fastvpn (Gluetun sidecar, renamed from `browseforge_vpn`) was removed 2026-11; since 2026-10-28 other users' BrowseForge profiles no longer route through a VPN (sidecar proxy settings removed at their owner's request). While they did (2026-10-23 → 2026-10-28), a stopped sidecar failed both profiles with the misleading error "persona contract mismatch: timezone policy must use persona-contract IANA timezone metadata" — worth knowing if a VPN sidecar ever returns.

## 7. openclaw
```bash
cd ~/docker-local/openclaw && kcs run --rm openclaw openclaw onboard   # FIRST: interactive wizard writes openclaw.json + provider key into the state volume; gateway refuses a LAN bind without it
kcs up -d
"$DK" ps -f name=openclaw --format '{{.Names}}: {{.Status}}'   # healthy (image entrypoint runs doctor --fix on every start; first start may take a minute)
```
Public check: https://openclaw.example.com — Control UI login is the gateway token from `openclaw/.env` (`OPENCLAW_GATEWAY_TOKEN`); that token is the auth story, no middleware. Headless bootstrap and channel pairing (Telegram/WhatsApp/…): docs.openclaw.ai/install/docker (Headless bootstrap, Configure channels).

## Final: public path
From outside the tailnet (phone with Tailscale off, or any external connection): open https://n8n.example.com — should load the n8n editor, no Cloudflare 502.
