# Agent Instructions (ultra-compressed; every obligation identical)

## 0. Test device, never production
**This = the Docker testing device.** Services only via `https://<service>.${BASE_DOMAIN}` (Cloudflare Tunnel → Traefik, §4) — never a published port or local URL. A domain here = **test setup** only, never production.

**Production = another device**: `ssh ${PRODUCTION_SSH_USER}@${PRODUCTION_SSH_HOST}`; values only in repo-root `.env` (§5.5, §8): `PRODUCTION_SSH_PASSWORD`, Docker dir `PRODUCTION_DOCKER_DIR`.

**Never push to production without explicit permission in the current conversation** (§6's bar): no commit/push/sync/copy/`rsync`/`scp`/`git push`/deploy to `PRODUCTION_SSH_HOST`/`PRODUCTION_DOCKER_DIR` — never on inference, standing instructions from earlier sessions, or "obviously belongs there". Raise, state what/where, wait for yes.

## 1. `compose.yaml` = zero comments; `.env` structured with section comments
`compose.yaml`/`docker-compose*.yml` carry zero comments — strip any found.
- **`.env` + `.env.example`**: section-divider comments (e.g. `# --- Domain Configuration ---`) required between logical groups (Domain/Global, Local Secrets, Stack Runtime, Resource Limits). `.env.example`: one `#` per key = meaning/allowed values/required; tag keys carry demo placeholders — never the real pin (§5.5). `.env` carries active values.

### 1.1 Interpolation: bare `${VAR}` or bare `${VAR:?}` — nothing else
- **`${VAR:?}`** = required gate: unset/empty fails the whole run (`required variable VAR is missing a value`; error names the key, no text in file). Use on values the stack can't run without (image tag, required secret, `BASE_DOMAIN`, `DNS_DOMAIN`) — refuses to come up rather than coming up misconfigured.
- **Forbidden**: `${VAR:?message}` (prose restates `.env`); `${VAR:-default}`/`${VAR-default}`/`${VAR:=default}` (substitutes a value the operator never set); `${VAR:-}` (empty default = no-op resolving as bare `${VAR}`). No default hides inside `${}`.
- Every value — tag, port, secret — in `.env`, visible/diffable/one edit away. Needed var → key + `${VAR:?}`; optional → bare `${VAR}`.

### 1.2 No hardcoded ports, URLs, domains, or addresses in `compose.yaml`
Compose = structure; `.env` = every environment-specific value. Host-side = bind-mount `source`, file supplied into a container, anything outside the compose project dir; in-project paths (`./api.env`, `./config`) and container-side paths are structure.
- **Externalize**: every port (container listen port, Traefik `loadbalancer.server.port`, `PORT`/`API_PORT`/`*_GRPC_PORT`-style env values, healthcheck-URL ports, `--listen` args); every URL/URI (`redis://redis:6379`, `*_BASE_URL`, `*_BROKER_URI`, `*_PUBLIC_BASE_URL`, allowed-origin lists); every domain/hostname (`BASE_DOMAIN`, `*_HOST`, the value inside a `Host(...)` rule); every host-side path.
- **Stays literal**: scheme + host when host = compose service name or self/wildcard in-container address — `http://127.0.0.1:${VAR_PORT}/healthz` (self healthcheck only, §4), `ws://0.0.0.0:${CODEX_APP_SERVER_PORT}` (listen address), `QDRANT_HOST: qdrant`, `REDIS_URL` host part; `https://` scheme before `${<STACK>_HOST}`; Traefik label *keys*; `websecure`; `letsencrypt`; container fs paths; literal non-env-specific flag values. Number/domain = variable; name = structure.
- **Naming**: container-side port `*_INTERNAL_PORT`; several ports on one service → by role (`OMNIROUTE_DASHBOARD_INTERNAL_PORT`, `QDRANT_HTTP_INTERNAL_PORT`, `QDRANT_GRPC_INTERNAL_PORT`). No `*_HOST_PORT` — nothing published (§4); §4's tailnet exception reuses `<STACK>_<ROLE>_INTERNAL_PORT` both sides. Domain keys: `BASE_DOMAIN` (bare, identical key every stack), `<STACK>_HOST=<service>.${BASE_DOMAIN:?}`, `<STACK>_PUBLIC_BASE_URL=https://${<STACK>_HOST}` when the app needs its own URL (a stack already naming it otherwise — `N8N_EDITOR_BASE_URL`, `PAPERCLIP_PUBLIC_URL`, `SUPABASE_PUBLIC_URL` — keeps its name; value still `https://${<STACK>_HOST}`). Never `<STACK>_BASE_DOMAIN` — one base domain, one key name host-wide. One value referenced twice = one key. Ports/URLs/domains change most per host/network/domain; visible in `.env`, a domain move = one edit per `.env`.
- **Sweep** before calling a service done, every `compose.yaml`, excluding none: `rg -n ':\d{2,5}\b'`; `rg -n '(https?|wss?|redis)://'`; `rg -n '^\s+ports:'`; `rg -n 'localhost|127\.0\.0\.1|host\.docker\.internal'`. Every `:port`/URL hit = `${VAR}`, service-name host + variable port, or UID:GID in a command (`chown -R 1000:1000` — UID is not a port). `ports:` returns nothing except `${TAILSCALE_IP}`-bound (§4). `127.0.0.1` only in a `healthcheck:`, self-bound listen/metrics address, or server-side self-URL the app calls on its own process (never browser-sent); `localhost`/`host.docker.internal` never. A hit = defect, not style.
- Secrets same rule, never literal: passwords, API keys, tokens, encryption/master keys.

### 1.3 Env: self-contained per stack, standard single-invocation
Every stack owns self-contained `.env` + `.env.example`; compose reads nothing external and nothing is passed via `--env-file`. Root `.env.global`/`.env.local` = maintenance-time sources only: `./sync-env` writes their values into stacks' `.env` — unprefixed keys — `BASE_DOMAIN` included — only into stacks whose `compose.yaml`/`.env` values interpolate the key (a stack may alias a global locally, e.g. openwa `OPENWA_TZ=${TZ:?}`, n8n `GENERIC_TIMEZONE=${TZ:?}`, network `DNS_DOMAIN=${BASE_DOMAIN:?}`); a stack that never interpolates a global keeps no copy of it.
- **Domain & secrets**: `BASE_DOMAIN` lives only where consumed — synced into stacks that interpolate it (`BASE_DOMAIN=` under the Domain Configuration section); `DNS_DOMAIN` likewise only where consumed — network aliases it locally (`DNS_DOMAIN=${BASE_DOMAIN:?}`); hostnames evaluate `<STACK>_HOST=<service>.${BASE_DOMAIN:?}` → Compose halts immediately if `BASE_DOMAIN` is unset/empty. Stack secrets (`network` needs `CF_DNS_API_TOKEN`, `CLOUDFLARED_TUNNEL_TOKEN`, `TS_AUTHKEY`) live in that stack's `.env`.
- **Standard invocation**: every compose command runs inside the stack dir, no `--env-file`: `docker compose <cmd>`.
- **Root `.env`**: agent/local tooling names only (`FIRECRAWL_API_KEY_*`, `PRODUCTION_SSH_*`, `DK` = engine CLI name consumed by BRINGUP.md snippets) — never consumed by compose. **Every engine/compose command resolves through `DK`, never a literal `docker`/`docker compose`** — per shell call: `DK="$(sed -n 's/^DK=//p' ./.env 2>/dev/null)"`; `DK="${DK:-docker}"`; engine `"$DK" ps`, compose `"$DK" compose up -d` (= BRINGUP.md's `kcs`; that function is paste-once for a human shell — agents re-expand per call, shell state doesn't persist across tool calls). `docker` on PATH (the engine ships a docker-compatible CLI) runs the same engine but bypasses the indirection — every literal `docker` example here, §6's read-only list included, reads `"$DK"` in real use.
- Sweep: `docker compose config -q` in the stack dir; any `variable is not set` = defect.

## 2. Serialization: one fixed entry order, every file
`compose.yaml`/`docker-compose*.yml`/`.env`/`.env.example` = **serialized**: same keys, same order, always → line-by-line diffs. Add/edit/reorder → key back in its slot. Ordering ≠ licence to add keys: unneeded key omitted, never an empty placeholder.

### 2.0 Naming: one stem per stack, every name derives from it
One stem + role suffix; lowercase, underscored, ASCII. Nothing named twice, nothing invented beside the stem.
| Artifact | Pattern | Single-service stack | Stack with a sub-service |
| --- | --- | --- | --- |
| stack `name:` | `<service>` | `name: cache` | `name: stack` |
| service key | `<service>`, or its role under the stack | `cache:` | `api:` |
| `container_name` | `<stack>_<service>` | `cache` | `stack_api` |
| network key + `name:` | `<stack>_net` | `cache_net` | `stack_net` |
| volume key + `name:` | `<stack>_<role>_data` | `cache_data` | `stack_cache_data` |
| `.env` vars | `<STACK>_<ROLE>_INTERNAL_PORT` / `<STACK>_HOST` | `CACHE_INTERNAL_PORT` | `API_HOST` |
| Traefik router + service | `<container_name>`, or `<container_name>-<role>` for further pairs on one service | `cache` | `stack_api` |
- Directory = stack = `name:` (`cache/compose.yaml` carries `name: cache`); the path is the naming input.
- Separator `_`, never `-` → `stack_api`, `stack_net`, `stack_cache_data` (compose accepts both; the constraint is this file's). Prefix dropped when service key = stack → `cache`, `queue`, never `cache_cache` (§2.2); sub-service keeps its role, takes the prefix → `client` → `stack_client` (a bare role is ambiguous host-wide).
- A joined network keeps the stem it was named for, never the joiner's: `worker` joins `cache_net`/`queue_net` `external: true`; creates none (they live in `net_anchor`, §4.1), renames none.
- Public hostnames: `-` replaces `_` → `evolution-go.${BASE_DOMAIN}`, `redis-insight.${BASE_DOMAIN}`, `camofox-vnc.${BASE_DOMAIN}`. DNS label = letters/digits/`-` only (RFC 952/1123; Let's Encrypt refuses `_`). Subdomain = stem `_`→`-`, plus `-<role>` for several routed ports on one service; `.env` key stays underscored (`EVOLUTION_GO_HOST`).
- One separator, always one `_` — `__` never (`browseforge_vpn_net`, `netbird_client_net`, `netbird_client_data`); multi-word stem: the directory name, one line above in `name:`, settles the boundary. Covers names *this stack mints* (`name:`, `container_name`, network/volume keys + `name:`, `.env` vars); not an application's own env-var keys — `CRW_SERVER__HOST`, `QDRANT__SERVICE__HTTP_PORT` are upstream strings, renaming silently unconfigures (documented as-is, §2.6).
- Spell `name:` on every top-level network/volume, own or external, key = value (`external` before `name`, §2.3).
- Omit what the service doesn't need → stateless tunnel: no `networks:`/`volumes:` block, no `-net`/`-data` name; a name is not a placeholder.
- `.env` reuses the stem, uppercased (`CACHE_INTERNAL_PORT`, `STACK_RUNNER_LAUNCHER_HEALTH_CHECK_PORT`); every value a `${VAR}` (§1.2).
- Rename = that one line + every place the old name is spelled: `labels`, operating commands, another stack's `external` join, a `.gitignore`. `container_name` change lands on next `up` — running container keeps old name until then; say so, never half-renamed.
- **Sweep** before done, every `compose.yaml`: `name:` == directory; `container_name` == table; network key + `name:` == `<owning-stack>_net`; volume key + `name:` == `<stack>_<role>_data`; a network `external: true` keeps its original stem, not the declaring stack's (§4.1). Miss = defect.

### 2.1 Top level (`compose.yaml`)
`name` → `x-*` → `services` → `networks` → `volumes` → `secrets` → `configs` → `include`; one blank line between blocks.
- `x-` = extensions, not elements: `x-logging: &default-logging` referenced as `logging: *default-logging`; `<<: *base` merges wholesale; spec *fragments*/*extension* are doc sections, never top-level keys. `x-` sits between `name` and `services` — an alias must reference an earlier anchor; alphabetise among themselves.
- An anchor = reuse device, not licence to hide keys: its block obeys the inline nested order (§2.2/§2.3); reordering keys away from it = defect.
- `include` = loads another Compose application/sub-domain; recursive, each file keeps its own project directory; resource-name conflicts warn, never merged.

### 2.2 Per service
Only needed keys, never out of order:
`image` → `pull_policy` → `container_name` → `hostname` → `command` → `entrypoint` → `user` → `working_dir` → `restart` → `stop_signal` → `stop_grace_period` → `security_opt` → `depends_on` → `cap_drop` → `cap_add` → `devices` → `environment` → `env_file` → `secrets` → `configs` → `read_only` → `expose` → `ports` → `dns` → `network_mode` → `networks` → `volumes` → `tmpfs` → `shm_size` → `ulimits` → `healthcheck` → `logging` → `deploy` → `labels`
Indent: 2 spaces per level, +2 per nested mapping, list items under their key.

House subset, not the spec's ~90 keys — an absent key is un-ordered, not forbidden; adding one = giving it a slot here first, natural position, never bolted on the end. **Forbidden, not un-ordered: `build`** (§9). `ports` holds a slot only for the §4 tailnet-IP-bound form; any other `ports:` entry forbidden.
- `pull_policy` = how the image is obtained: `always`/`never`/`missing` (default; legacy alias `if_not_present`)/`build`/`daily`/`weekly`/`every_<duration>` — how §5.4's "newest stable, then pin" survives §6's `docker compose pull` ban: the fetch decision lives in the file. `missing` still pulls `latest`; §9 forbids that anyway.
- `secrets`/`configs` sit with `env_file`, the file-injection keys, matching §2.1's order. Service-level grants of a top-level declaration; service key mounts it (`target`/`uid`/`gid`/`mode`); read-only by nature.
- Five isolation keys, one group: `security_opt` right after the restart/stop keys (what the process may escalate to); `cap_drop` → `cap_add` after `depends_on` (drop-then-grant pair, never reversed/non-adjacent); `devices` immediately after `cap_add` (a device node is a kernel-interface grant — `/dev/net/tun` is privilege, read with the caps); `read_only` immediately before `expose` (every write must land on a `volumes:` target or `tmpfs:` mount, else crash-loop at startup).
- A `cap_drop`/`cap_add` pair is not mandatory: default-set caps re-granted with `cap_add` alone (`FOWNER`, `SETUID`) = no-op — the drop makes such a grant real; non-default caps (`NET_ADMIN`, `SYS_ADMIN`, `SYS_RESOURCE`) need `cap_add` alone. Tighter posture = `cap_drop: ALL` + exactly what's needed, never a requirement; broad `SYS_ADMIN` legitimate where upstream asks; set only where the entrypoint needs headroom (hardened image: `cap_drop: ALL` + exactly `CHOWN`/`DAC_OVERRIDE`/`FOWNER`/`SETGID`/`SETUID`, root entrypoint chowns the data volume then `gosu`-drops). §3's `pids_limit`/`mem_limit` ban unaffected — ceilings go in `deploy.resources.limits`.
- `network_mode` occupies the `networks` slot — mutually exclusive (compose rejects both): a sidecar sharing another service's netstack writes `network_mode: "service:<name>"` where `networks` would sit, omits `networks`. Never `host` (§4).
- `container_name` on every service, third key: `<stack>_<service>`, lowercase, underscored. Host-global; the stack prefix keeps same-role stacks from clashing (else Docker invents `<stack>_<service>-1`); prefix dropped when service name = stack → `stack`, not `stack-stack`. Literal, not `${VAR}` — derived from `name:` + service key, both in the file; a variable could only drift (§1.2 governs env-specific values; a name is structure). Never a service→service address — inter-service uses the service name (§4); `container_name` = operator's `docker logs`/`exec`/`inspect` handle only. Cost: a named service cannot scale — `--scale` refused, `replicas` stays 1; scaling = compose edit.

### 2.3 Nested keys
- `healthcheck`: `test` → `interval` → `timeout` → `retries` → `start_period` → `start_interval` (spec v2.20.2; `disable: true` is the alternative to `test`, not a slot)
- `deploy.resources`: `limits` only; inside each `cpus` → `memory` → `pids`.
- `logging`: `driver` → `options`; `logging.options` alphabetical
- `volumes` (long form): `type` → `source` → `target` → `read_only` → `bind`
- `labels` (Traefik routing, §4): non-Traefik labels first → `traefik.enable` → `traefik.docker.network` → `traefik.http.middlewares.*` → `traefik.http.routers.<name>.rule` → `.priority` → `.entrypoints` → `.middlewares` → `.tls` → `.service` → `traefik.http.services.<name>.loadbalancer.server.port`. No `.tls.certresolver`/`.tls.domains[*]` slots — the wildcard cert is entrypoint-level (§4); a service router never requests a cert.
- top-level `volumes`/`networks` defs: `driver` → `driver_opts` → `ipam` → `external` → `name` → `labels`; trailing `name`/`external: true` may be last

### 2.4 `environment:` and `.env` share one order
`environment:` keys follow their variables' `.env` order. `.env` grouping: **image vars first** (so `image:` resolves) → **service runtime vars** in its `environment:` order → **routing vars** (internal ports, anything only a Traefik label reads) → **anything else**. `BASE_DOMAIN` → `<STACK>_HOST` → `<STACK>_PUBLIC_BASE_URL` always in that order (each interpolates the one before), wherever first consumed. `.env.example` = `.env`'s exact key order → row-for-row alignment.
- A var several services share (common `*_BASE_URL`, shared secret) = **one** key, one value, same relative slot in each consumer's `environment:` → each service's list a subsequence of the one `.env` order. Never duplicated per service, never differing values.
- Grouping exception: a key another key interpolates is defined earlier — `.env` resolves top-down; `CACHE_URL=cache://cache:${CACHE_INTERNAL_PORT}/2` above a later `CACHE_INTERNAL_PORT=` silently renders `cache://cache:/2`, compose only *warns*. Inner key first; verified against `docker compose config`.

### 2.5 Worked example
Fictional three-service stack, images invented — never lift a real service's config from this repo as the reference. Obeys §1–§4; where example and rule disagree, rule wins; keys appear only where relevant.
**Machine-validated** (`docker compose config`, CLI v5.6.1): exit 0, empty stderr, 150 lines — 150 only with the `X=1` `api.env` fixture; empty fixture = 149 (missing `env_file` merge line); absent fixture exits 1 (`env file … not found`). Verified: `x-logging` anchor expands to `driver` + alphabetised `options` in all three; long-form `env_file` (`required: true`) merges into `environment` (`X: "1"`); deleting `API_IMAGE_TAG` stops at the §1.1 gate; `depends_on: restart: true` takes effect. Long form for `volumes`/`env_file` because §2.3 orders their explicit fields (`type`/`source`/`target`, `path`/`required`). No `ports:` — `api` routed via Traefik labels on external `traefik_net`; re-validated 2026-11-16 post-healthcheck-restoration: exit 0/150 with fixture, ``Host(`api.example.com`)``, `PUBLIC_BASE_URL: https://api.example.com`, `tls: "true"`, no certresolver/domains labels; validating needs no running Traefik (`external` network unchecked).

```yaml
name: stack

x-logging: &default-logging
  driver: json-file
  options:
    max-file: "3"
    max-size: 10m

services:
  api:
    image: acme/orders-api:${API_IMAGE_TAG:?}
    container_name: stack_api
    command: ["serve", "--port", "${API_INTERNAL_PORT}"]
    user: "10001:10001"
    restart: unless-stopped
    stop_grace_period: 30s
    depends_on:
      cache:
        condition: service_healthy
        restart: true
    environment:
      CACHE_URL: ${CACHE_URL}
      LOG_LEVEL: ${LOG_LEVEL}
      PUBLIC_BASE_URL: ${API_PUBLIC_BASE_URL}
    env_file:
      - path: ./api.env
        required: true
    networks:
      - stack_net
      - traefik_net
    tmpfs:
      - /tmp:size=64m
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:${API_INTERNAL_PORT}/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging: *default-logging
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
          pids: 256
    labels:
      com.example.role: api
      traefik.enable: "true"
      traefik.http.routers.stack_api.rule: "Host(`${API_HOST}`)"
      traefik.http.routers.stack_api.entrypoints: "websecure"
      traefik.http.routers.stack_api.tls: "true"
      traefik.http.services.stack_api.loadbalancer.server.port: "${API_INTERNAL_PORT}"

  worker:
    image: acme/orders-worker:${WORKER_IMAGE_TAG:?}
    container_name: stack_worker
    command: ["work", "--concurrency", "8"]
    user: "10001:10001"
    restart: unless-stopped
    stop_grace_period: 1m
    depends_on:
      cache:
        condition: service_healthy
        restart: true
    environment:
      CACHE_URL: ${CACHE_URL}
      LOG_LEVEL: ${LOG_LEVEL}
    networks:
      - stack_net
    volumes:
      - type: volume
        source: stack_worker_data
        target: /var/lib/worker
    healthcheck:
      test: ["CMD", "worker", "ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    logging: *default-logging
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
          pids: 512

  cache:
    image: acme/ratelimit-cache:${CACHE_IMAGE_TAG:?}
    container_name: stack_cache
    restart: unless-stopped
    stop_signal: SIGTERM
    stop_grace_period: 30s
    environment:
      CACHE_MAXMEMORY: ${CACHE_MAXMEMORY}
    networks:
      - stack_net
    volumes:
      - type: volume
        source: stack_cache_data
        target: /data
    healthcheck:
      test: ["CMD", "cache-cli", "ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging: *default-logging
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 384M

networks:
  stack_net:
    driver: bridge
    name: stack_net
  traefik_net:
    external: true
    name: traefik_net

volumes:
  stack_worker_data:
    name: stack_worker_data
  stack_cache_data:
    name: stack_cache_data
```

Matching `.env`, §2.4 order — image vars for all three, runtime vars in `environment:` order, routing (`API_INTERNAL_PORT`) last; `CACHE_INTERNAL_PORT` ahead of `CACHE_URL`, `BASE_DOMAIN` ahead of `API_HOST` (interpolated keys first):

```sh
API_IMAGE_TAG=2.4.1
WORKER_IMAGE_TAG=2.4.1
CACHE_IMAGE_TAG=7.2-alpine
CACHE_INTERNAL_PORT=6379
CACHE_URL=cache://cache:${CACHE_INTERNAL_PORT}/2
LOG_LEVEL=info
BASE_DOMAIN=example.com
API_HOST=api.${BASE_DOMAIN}
API_PUBLIC_BASE_URL=https://${API_HOST}
CACHE_MAXMEMORY=256mb
API_INTERNAL_PORT=8080
```

`CACHE_URL` = one key holding the whole URI → its port can't drift from `CACHE_INTERNAL_PORT` (§1.2). Only `api` routed: `traefik_net` + labels, `tls: "true"` only — the `websecure` entrypoint owns the wildcard cert (§4); `worker`/`cache` internal — no labels, no `traefik_net`, service name on `stack_net`. `cache` carries `healthcheck:` because both dependents gate `condition: service_healthy` — a dependent on a service with no healthcheck never starts. Networks + volumes spell `name:` = key (§2.0); `.env` interpolation order per §2.4.

### 2.6 Where the order lives
Single source of order: the compose file shows it, §2.2–§2.4 enforce it; no per-service file restates it.

## 3. Resources: ceiling, per service
**Mandatory on every service** in `deploy.resources`: a ceiling. Missing ceiling → unfinished. Minimal values that still run (§3.1) beat roomy guesses — the ceiling is the only half compose enforces. Never the mirrors `mem_limit`/`cpus`/`pids_limit` — two places to sync is one too many.

```yaml
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
          pids: 256
```

| Want | Key | Format | Notes |
| --- | --- | --- | --- |
| Max CPU | `limits.cpus` | string cores, `"0.50"` | Fractional. `"0.000"` = *no limit* — never write it |
| Max RAM | `limits.memory` | byte string, `512M` | Units `b`, `k`/`kb`, `m`/`mb`, `g`/`gb`; no `t`. Exceeding = OOM kill, not slowdown |
| Max procs | `limits.pids` | integer | Caps fork bombs, runaway workers |

- **Storage**: no `deploy.resources` key — Compose can't cap a volume. `tmpfs: - /tmp:size=64m` = real RAM cap; full fs fails writes instead of filling host disk — right tool for scratch. A persistent volume is bounded by the host fs, not this file — unbounded and watch, or dedicated small fs. `blkio_config` Swarm-only — never use.
- Other `deploy` keys (`replicas`, `placement`, `restart_policy`, `update_config`) Swarm-only, ignored; only `deploy.resources.limits` is enforced on `up` — always set. Schema verified against CLI v5.6.1 (API 1.47) + the Compose Deploy Specification; `limits` enforcement verified live — cgroup ceilings read from the running anchor (`memory.max`/`cpu.max`/`pids.max`).

### 3.1 Setup menu — minimal-first profiles
Pick a **profile**; never invent numbers. Default **P1**; above/below needs one line of justification (workload forcing higher, or idle enough for lower). Values = starting points; the workload owns the finals.

| Profile | `limits.cpus` | `limits.memory` | `limits.pids` | Pick when |
| --- | --- | --- | --- | --- |
| **P0 Nano** (lightest) | `"0.25"` | `96M` | `64` | Truly idle daemons: an anchor service, a socket proxy, a one-shot admin/CLI container — near-zero steady work |
| **P0 Micro** | `"0.50"` | `256M` | `128` | Small but continuously active: DNS, VPN sidecars, a static/nginx reverse proxy, a tunnel carrying light traffic |
| **P1 Minimal** (default) | `"0.50"` | `512M` | `128` | Dev/test, one client, light query load. The default for a new service |
| **P2 Balanced** | `"1.50"` | `1G` | `256` | Shared host, a handful of app services, steady OLTP |
| **P3 Roomy** | `"4.00"` | `4G` | `1024` | Heaviest workload in the stack, or a JVM/ML/vector index that sizes itself from RAM |
| **P4 Custom** | — | — | — | A service whose own docs state hard minimums (a JVM heap floor, an index that mmaps). Cite the source, else it is P1–P3 |

- Profile never half-set — all three limits, always; `"0.000"` = no limit → never write it.
- Disk is not in the menu — scratch → `tmpfs` with `size=`; persistent → host fs, watched, never pretended otherwise.
- The memory ceiling must clear what the service allocates for itself (`shared_buffers`, JVM `-Xmx`, vector-index `mmap`): if `limits.memory` is under the service's own documented minimum, the profile is wrong, not the service — check the service's docs before picking.

**Image and tag, per service, before any profile:** `image:` only, `repo:tag`, tag from `.env` (§9, §1.2); pin — never `latest`/`main`, never floating; smallest variant that runs the workload (`-alpine` where the service tolerates musl). No published pre-built image = **gap, not a task** (§9) — report, never build.

**Order of operations, every service:** research (§5) → report findings → **wait for the go** → write `compose.yaml` + `.env` + `.env.example` → `docker compose config` (must pass) → pick profile, state it → hostname unclaimed (`rg -n 'Host\(' */compose.yaml`, `rg -n '_HOST=' */.env`) + no `ports:` slipped in → ask before the first `up` (§6). A profile chosen before `config` passes = a guess.

## 4. Networking: domain-only, nothing published
Path, fixed: client → Cloudflare edge → **Cloudflare Tunnel** (`cloudflared` stack, outbound-only, one dashboard route `https://traefik:443` for every hostname) → **Traefik** (`traefik` stack, `websecure` entrypoint, wildcard TLS — entrypoint carries `certresolver=letsencrypt` + domains `${BASE_DOMAIN}` / `*.${BASE_DOMAIN}` via `TRAEFIK_ENTRYPOINTS_WEBSECURE_HTTP_TLS_*` env, resolver does Cloudflare DNS-01; every service router rides that one wildcard with `tls: "true"`, never requests its own; Docker provider `exposedbydefault=false` on `traefik_net`) → the service, matched by `Host`. No host port opened → nothing reachable by IP, port, `localhost`, or LAN — except the tailnet-IP-bound `ports:` form below.
- **No `ports:` — ever, any service, any form — one named exception.** Not loopback (`127.0.0.1:3000:3000`), not bare, not `0.0.0.0`, not long form, not "temporarily". Traefik reaches services over Docker networks; `expose:` allowed (documentation only). Found `ports:` = defect to raise (strip when editing, §1) unless the exception.
- **Exception — tailnet-IP-bound `ports:` only**, allowed **iff** binding the Mac's Tailscale IP and nothing else, exactly: `"${TAILSCALE_IP:?}:${<STACK>_<ROLE>_INTERNAL_PORT}:${<STACK>_<ROLE>_INTERNAL_PORT}"` (+`/udp`/`/tcp` where protocol matters). Never `0.0.0.0`, loopback, bare `IP:port`, or a second host-side variable — one value, one key, never `*_HOST_PORT` (§1.2). `100.64.0.0/10` = CGNAT → answers only to tailnet peers, never LAN/public/localhost. Each entry carries a justification: what must reach it over the tailnet, why Traefik or a docker network can't. §1's sweep exempts exactly these.
- **No local URLs anywhere a human or another host reads**: `http://127.0.0.1:…`, `localhost`, `host.docker.internal`, `127.*`, `192.168.*`, `10.*`, `172.*`, any LAN/host IP stay out of `*_PUBLIC_BASE_URL`/`*_BASE_URL`/callback/allowed-origin values, `depends_on` wiring. No `network_mode: host`.
- **Browser/client access = a domain, nothing else:**
  - `.env`: `BASE_DOMAIN` (same key in every stack that carries it), `<STACK>_HOST=<service>.${BASE_DOMAIN}`, `<STACK>_PUBLIC_BASE_URL=https://${<STACK>_HOST}` when the app must know its own URL (§1.2, §2.4).
  - Network: joins `traefik_net` `external: true` (owned by `net_anchor`, §4.1); never `cloudflared_net` — only Traefik does.
  - Labels (§2.3 order), router + service name = `container_name`: `traefik.enable: "true"`; ``traefik.http.routers.<name>.rule: "Host(`${<STACK>_HOST}`)"``; `.entrypoints: "websecure"`; `.tls: "true"`; `traefik.http.services.<name>.loadbalancer.server.port: "${<STACK>_INTERNAL_PORT}"`. **Never `.tls.certresolver`/`.tls.domains[*]`** — defect (strip when editing, §1). Several web ports on one service → one router+service pair per role, each its own `<STACK>_<ROLE>_HOST`; pair names = `<container_name>` + `-<role>` (`n8n-public`, `camofox-vnc`), and the shared service behind a split keeps the bare `<container_name>` (`postiz_nginx`).
  - Hostname = `<service>.${BASE_DOMAIN}`, one subdomain level — covered by the wildcard cert (`*.${BASE_DOMAIN}`) + Cloudflare Universal SSL. Never a path-prefix route (`${BASE_DOMAIN}/<service>`); never a second-level subdomain (`a.b.${BASE_DOMAIN}` — neither wildcard covers). Named exception, not precedent: a path-restricted public/private split on one hostname (n8n's `PathPrefix(`/webhook`)` public router over a `tailnet-only` private one, postiz's `/uploads`) when the service needs both — public router priority 100 + `PathPrefix`, private router priority 10 + the `tailnet-only@docker` middleware, one shared service.
  - No tunnel or DNS change per service; a hostname outside `*.${BASE_DOMAIN}` = tunnel/dashboard change — raise, don't assume.
- **Non-HTTP services stay internal** — no domain, no port. Databases, caches, queues, gRPC, DNS/UDP, VNC, raw TCP: reached by other services on a shared Docker network; human access via an HTTP admin UI that itself gets a domain (pgAdmin, Redis Insight, noVNC). No Traefik TCP/UDP routers — Cloudflare Tunnel doesn't carry raw TCP/UDP without `cloudflared access` client-side; needed from outside → raise.
- **No domain needed → no labels, no `traefik_net`**: `exposedbydefault=false` never routes an unlabelled container; joining without labels = clutter, not access.
- **Auth = the service's job, or a middleware's.** Every routed service: own login, Traefik middleware (`basicauth`, forward-auth), Cloudflare Access, or the `tailnet-only@docker` ipallowlist middleware (defined once in the `network` stack on `${TAILNET_ONLY_SOURCE_RANGE}`) — default for admin/CI-facing with no public need. Routed service with no auth = defect to raise before the first `up`. A path-restricted split may keep one `PathPrefix` public by design — record which paths and why.
- **Service→service**: shared Docker network, hostname = service name, container's internal port (`http://api:3000`, `http://db:5432`) — never the public domain (no hairpin through Cloudflare). Container-side port = `.env` variable (§1.2). Internal HTTP correct; TLS terminates at Cloudflare and again at Traefik. Backend HTTPS only if the service itself speaks TLS — add `traefik.http.services.<name>.loadbalancer.server.scheme: "https"`.
- Health checks and inter-service URLs use the service name — restarts don't depend on host state, DNS, or the tunnel. **A health check aimed at the service's own container uses `127.0.0.1`**, not its service name or domain — it runs *inside* the container; Docker DNS or the public domain adds a dependency to the most local test in the file. The one place `127.0.0.1` may appear (plus a listen/metrics address the container binds for itself): service name for **inter-service**, loopback for **self**. `healthcheck:` involves no published port.
- **Hostname collision** replaces the old port collision: before `<service>.${BASE_DOMAIN}`, check unclaimed (`rg -n 'Host\(' */compose.yaml`, `rg -n '_HOST=' */.env`). Two routers on one `Host` → Traefik picks by priority, silently. On collision pick a distinct subdomain; say plainly which hostname moved and why.
- **Dependency:** a routed service is unreachable until `net_anchor` → `traefik` → `cloudflared` are up and the tunnel token is set. Starting any = §6 — ask.

### 4.1 One owner per network: `net_anchor` owns every one
Every network owned by `net_anchor`, declared there `driver: bridge` + `name:`; every other stack joins `external: true`, never creates/renames/removes — no single-consumer exception: even a network only one stack joins stays in `net_anchor` (operator decision 2026-11-01, superseding "one consumer stack owns it").
- **Mechanical**: every network name any stack references appears in `net_anchor/compose.yaml` (`driver: bridge` + `name:`) and in every other stack `external: true` + same `name:`.
- The name keeps its original stem — `postgres_net`, `traefik_net`, never `net_anchor_net` (§2.0 fixes the name, §4.1 who calls create).
- **A joiner stays `external: true` — for `down`, not for `up`.** Re-declaring a shared network `driver: bridge` does **not** break the next `up`: `NetworkHash` covers only the network's own fields (name, driver, `driver_opts`, `ipam`, `internal`, `attachable`, labels, `enable_ipv4/6`); compose-go tags `CustomLabels` `json:"-"` so the project label never enters — `net_anchor`'s first `up` adopted 8 pre-existing networks, warning only, no recreation (verified live 2026-10-09). What *does* trigger `removeDivergedNetwork` — that stack's containers **stopped, disconnected, network deleted** before recreation — is a declaration differing in any hashable field: an added `ipam`, a changed driver, a network `labels:` block. Keep every joiner's declaration field-identical to `net_anchor`'s. `external: true` stops a joiner's `down` from deleting a network its peers attach to.
- Warnings on `net_anchor`'s `up` = expected noise: one `a network with name <x>_net exists but was not created for project "net_anchor"` per pre-existing network — the project label can't match; cosmetic, nothing recreated.
- **Never hand-create**: bare `docker network create` leaves `com.docker.compose.network` empty → hard error `network <x>_net was found but has incorrect label … set to ""`. Networks come only from `docker compose up` in `net_anchor/`.
- **Add**: declare in `net_anchor/compose.yaml` (`driver: bridge` + `name:`) + attach its one service; consumers join `external: true` + same `name:`. **Remove**: strip every join, re-`up` those stacks, drop from `net_anchor/compose.yaml`, `up -d`, then `docker network rm <name>` — refuses while anything is attached.
- A fresh host starts `net_anchor` first. No `depends_on` expresses it — the dependency crosses compose projects.

## 5. Research a service before proposing or adding it
Partial pictures → wrong compose, missing dependencies, violated rules. Collect all — complete catalogue, not a usable subset:
1. What it does, architecture, problems solved + benefit: what capability/workflow/cost-ops it adds here, whether an existing service already covers it.
2. Official image and version: repo, tags, architectures, upgrade/pinning, cadence — and that a pre-built image exists (§9).
3. Configuration surface: **the whole** config file / CLI flag / env var / runtime-parameter surface — not the subset used — meaning, allowed values, default, required; mark security (secrets/tokens/auth), networking, storage, resource implications.
4. Runtime: container user/UID:GID, filesystem layout + permissions, writable paths, storage backends/volumes, CPU/RAM expectations.
5. Ports, healthcheck endpoint, first-run setup/bootstrap (admin account, schema migration, seed data).
6. Sidecars/companions — cache, database, search index, object store, queue, metrics/log shippers, auth/SSO, secret store, migration/backup — optional vs effectively mandatory; also ones that make no sense on this host.
7. Auth model, license/edition tiers, deployment constraints (a sidecar that must be public for callbacks, a needed proxy, a paid-tier-only feature).
8. Gotchas: breaking changes between versions, required kernel features, unsupported filesystems, upstream-documented caveats.

Prefer the service's own docs + official compose examples over blogs/summaries. **The catalogue is exhaustive; relevance is not a filter** — every env var, config file/flag, CLI subcommand, runtime parameter, sidecar, image variant upstream documents, including unused, paid-tier, single-host-implausible — each with a status. **Unconfirmed means labelled, not deleted** (fetch failed, 404, contradicting docs, seen only in an example → mark ✅ verified / ✗ unverified, name it in the report; never remove an entry because a search came back empty — upstream Markdown escapes underscores, normalise escapes, re-run a second pattern). Prove coverage mechanically before claiming completeness: harvest every variable-shaped token (`[A-Z][A-Z0-9_]{3,}`) from every page fetched, expand brace groups in full (`PREFIX_{A,B}` → both names), diff, report `N/N documented, 0 fabricated`.
**The gate, when adding a service or proposing a change: research → report findings → wait for the user's go → only then write `compose.yaml`/`docker-compose*.yml`/`.env`/`.env.example`.** The report is the last thing before asking; compose content written after an explicit yes, never the same turn as the research. One exception, not a go: a request already scoped to editing existing compose content. Research material never goes into compose/`.env` — purely declarative, only values the service needs; why/alternatives/operation notes → the report.

### 5.4 Currency: latest configuration only, never stale
- **Verify upstream live, every time, before writing or confirming a config** — tag list, release page, the service's docs, at the moment of the task (§8, Firecrawl). A fact from an earlier turn or training knowledge is **not** verified — a version from memory = a guess with a date on it.
- **Unknown ⇒ research, then configure.** Never ship a version, tag, flag, env var, path, or default not confirmed in this task; "I am fairly sure 18.6 is current" is not a source — the tag page is. Unconfirmable → labelled ✗ in the report, never a `compose.yaml` value.
- **Newest stable, then pin it**: newest *stable* release of the newest stable major — not floating `latest`/`main`, not a pre-release (`alpha`/`beta`/`rc`/`-beta4`) unless asked. Pinned = reproducible, current = not behind; the pin written **only** to the gitignored `.env` (§5.5).
- **Currency spans the whole config surface**: env var names + existence, defaults, file paths, volume targets, healthcheck commands, CLI flags/subcommands, GUCs, compose keys, the documented setup route itself (an init-hook or `command:` upstream replaced). Removed/renamed/deprecated → reported as such, never silent.
- **Re-verify before asserting currency in a reply** — a fetch behind it + the reply states the fetch date; without, say what is unverified.
- **Never raise a major on your own** — a newer major is a report item (breaking changes, migration path, data-format change, rollback); the upgrade written only after the go. Current major + newest minor = the correct default state, not an oversight.
- Findings that change a written config: raised first, applied after the go (§5). Research never silently rewrites what is on disk.

### 5.5 No versions in committed files
A running version fingerprints the deployment and targets it at known CVEs. The real image tag — and any OCI digest — lives **only** in the gitignored `.env`; no committed file ever states a running version, tag, or digest, past or present. A secret's real value likewise lives **only** in the gitignored `.env` — committed files and replies carry the key name and purpose, never the value (§8).
- `.env.example` fills the tag key with a **demo placeholder** shaped like the real value — same type and length (`NET_ANCHOR_IMAGE_TAG=9.9.9`), never the real pin; demo values throughout (operator decision 2026-11-15). Each key's comment documents the value format (`X.Y.Z`, `vX.Y.Z`, `X.Y.Z-alpine`, `YYYY.MM.P` calver, `sha256:<64 hex chars>` digests), never a real value.
- Committed docs reference the tag only as "pinned via `${VAR}` in `.env`". No "newest stable at write time" claims, no version-history narrative. Records of removals keep the *event* (an image removed, a stack recreated), never the tag live at the time; operational dates not tied to a version claim stay.
- Upstream's own facts stay: compatibility floors (PostgreSQL ≥ 14), tested matrices, versioned config values the image reads (`ES_VERSION=v7`) are upstream docs, not this deployment's versions.
- The pin is still pinned (§9): `repo:tag` via `${VAR:?}`, never `latest` — only the *recording* changes; reproducibility lives in the gitignored `.env` — accepted trade-off.

## 6. Never start or stop services without permission
The running state is the user's alone. Never without explicit permission in the current conversation — even harmless, temporary, "just check". Never without a yes:
- `docker compose` `up`/`down`/`start`/`stop`/`restart`/`pause`/`unpause`/`kill`/`scale`/`pull`/`--watch` — any form, any service, single/profile/detached included.
- `docker build`, `docker compose build`, `--build`, `buildx`, `buildah` — never, even with a standing yes (§9 out of scope); report the need.
- `docker run`, `docker start`, `docker exec` into a not-running container, or any other way to bring one up.
- Recreating/replacing a container — a config change takes effect only on the next `up`; don't trigger it.
- Anything long-lived/background: dev server, tunnel, proxy, tunnel connector.

`down`/`stop` are state changes — ask first. Can't verify without running → say so, stop, ask exactly which service/what command/why, wait. Always allowed, no asking — read-only: `docker compose config`, `docker compose ps`, `docker ps`, `docker logs`, `docker inspect`, `docker stats --no-stream`, `docker diff`, read-only commands inside running containers.

## 7. Databases and volumes are read-only
**Read** — and only read — volumes and databases (PostgreSQL or any other): inspect schemas, list tables, dump data, read logs/config files. That is all. Never without explicit permission in the current conversation:
- Any write/DDL/DML — `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `CREATE`, `ALTER`, `DROP`, migrations, seeding, an app's migration/bootstrap against a live database.
- Creating/modifying/moving/deleting anything in a volume — files, `chown`/`chmod`, moving data, pruning, editing config/credential files.
- State-changing commands in a running DB/app container — modifying `psql`, `redis-cli SET`, cache/queue flushes, index rebuilds/reindexing.
- Volume lifecycle — reset, restore, snapshot, `docker volume rm`, wiping a data directory, `down -v`.
- Changing `.env` values or credentials a running database depends on.

Needed? Stop, ask — exactly what, against which service, why — then wait. Read-only diagnostics always allowed. **Read means read**: even a "harmless" write (temp table, test row, `VACUUM`, an index to speed a query) modifies state. Never create test data anywhere.

## 8. Web access: Firecrawl direct API, never MCP
All web ops (search, fetch, scrape, crawl, map, extract, md/html conversion) via Firecrawl. Never `webfetch`/`websearch`/browser tools; Firecrawl fails → report the error, never fall back to a native tool. Key: `FIRECRAWL_API_KEY` env var; never hardcode credentials.
- **REST API, not MCP**: `POST https://api.firecrawl.dev/v2/<endpoint>`, headers `Authorization: Bearer $FIRECRAWL_API_KEY` + `Content-Type: application/json`. MCP not installed and must not come back; the plugin bundle is not the install path (carries MCP config).
- **Markdown first, always.** Every op requests markdown; HTML = fallback, never default. `rawHtml` only once markdown proves insufficient (truncation/conversion loss, or exact-bytes machine-readable file) — say which case forced it.
- **Output → `.firecrawl/<topic-or-service>/`**, one level, never loose at root, never elsewhere. Folder = the service's directory stem (§2.0) when serving one service, else a lowercase-underscored ASCII topic slug (`compose_spec`, `firecrawl`); picked before the first call of a batch, reused for the whole batch — one pass, one folder, never per page, never deeper. File name from the **URL**, not the title: `<host>__<path>`, `/` → `_`, rest stripped (`docs.docker.com__reference_compose_file.md`). Extension = format, same base name: `.md` markdown, `.html` the rawHtml fallback, both kept — fallback sits beside the conversion it replaced.
- **Reuse before fetching** — `.firecrawl/` is a corpus, consult first (`rg`, Read). Cached content counts for discovery/background; satisfies §5.4's live verification only when re-fetched in the current task. Cache learns *which* URL answers a question; fetch live when the answer feeds a written config.
- **Exact bytes matter → `rawHtml`**: markdown escapes frontmatter (`\-\-\-`) and backticks, silently corrupting machine-readable files (`SKILL.md`, lockfiles, configs); `rawHtml` returns the original text — unescape the one wrapper element.
- **Skills live in `.claude/skills/`, project level, byte-identical copy in `.agents/skills/`.** `firecrawl` = the reference for this mechanism — read before improvising; where it differs, this section wins. No CLI skill installed, none to be added (CLI not on this device; shipped skill held dangling pointers). Load by exact ID = directory name; `name:` in frontmatter = display label. `.claude/skills/` = what Claude Code discovers; `.agents/skills/` = portable Agent Skills location Cursor/third-party clients read. Update both in one commit or they drift. **Never a symlink** — Claude Code skips a symlinked `.agents/skills/`, the copy fails silently.
- **Keyless is a fallback, never a plan.** Keyless `search`/`scrape`/`interact`/`parse` work only through an official client (MCP, CLI, SDK); raw keyless API call refused — we hold a key → always send one. `crawl`/`map`/`monitor`/`extract`/`batch`/`agent` need a key regardless. A keyless refusal is **not** a rate limit: don't rotate, add the key.
- **Keys live in `.env`, never here.** Pool = `FIRECRAWL_API_KEY_1` … `_N` in the repo root `.env`; values never in `AGENTS.md`, a compose file, a committed file, or a reply — variable names only. Pool size = whatever `.env` holds; count the `_N` vars, never assume. **Live pool = the `^FIRECRAWL_API_KEY_[0-9]+=` lines sorted by index; a gap in numbering is normal.** A spent key renamed in place `FIRECRAWL_API_KEY_EXHAUSTED_<n>` — index preserved, value clearable; not pool, skipped on rotation.
- **Session start → pick one at random** from the live index list — never `1..count` (a gap makes `count` ≠ `max`, landing on an index with no key). `export FIRECRAWL_API_KEY="$FIRECRAWL_API_KEY_<n>"`; say which index once, don't re-pick mid-session; a new session re-randomises. Each shell call = fresh process → re-source/re-export in every call touching Firecrawl.
- **Rate limit → rotate, don't give up.** On quota rejection (429, `RATE_LIMIT`, "exceeded"), move to the next **live** key in sorted order (skip gap indices and `_EXHAUSTED_`, never blind `n+1`), retry the same call; exhaust the whole live pool before reporting failure. Rotate on rejection only — never speculatively, mid-call, or in parallel fan-out. Rotation = one `export` in the calling shell. Never dodge a limit via a native tool.

## 9. Pre-built images only, never a build
Configuration, not construction.
- `image:` only, always `repo:tag`, tag from `.env` (§1.2), newest stable at the moment written (§5.4). Never `build:` — no `context:`/`dockerfile:`/`args:`/inline Dockerfile; §2.2's order omits `build` because it never appears.
- No `Dockerfile` anywhere: never create, edit, point compose at, or propose one — service directory or repo root.
- Never run a build: `docker build`, `docker compose build`, `--build`, `buildx`, `buildah`, any wrapper. Ask before running (§6); the standing answer is no.
- No source substitutes: no `git clone`, `npm install`, `pip install`, `go build`, `cargo build`, `make`, `cmake`, hand-assembled base images.
- **No published pre-built image = a gap, not a task.** Report what's missing, whether an official image, maintained community image, or hosted SaaS fits, what building costs. The operator decides; never close the gap with a build.
- Verified in `docker compose config`: every service resolves to a registry `image:`, no `build:`, no tag floating on `latest`/`main`.

## 10. File name and format: `compose.yaml`, Compose Specification
Precedence: `compose.yaml` (**canonical, preferred**) → `compose.yml` → `docker-compose.yaml` → `docker-compose.yml`. Write `compose.yaml`; never author the others; a legacy file renamed when touched, rename stated in the reply. One file per directory: two of the four side by side = a defect, not an override layer — the second is silently ignored. §1's `docker-compose*.yml` glob = the legacy name only, never a licence to author one.
- Format = **Compose Specification**, versionless — no top-level `version:` (obsolete, only warns); §2.1's order starts at `name`.
- CLI = `docker compose` (v2+ plugin); `docker-compose` (v1, Python) removed, unsupported — never invoke or document it.
- **Toolchain gate** — this device runs `docker compose` **v5.6.1** (local compose engine plugin). Keys spec-gated above local are unusable, rejected outright; `pre_start` (init containers, spec-gated **v5.3.0**) is supported. Check a version-gated key against `docker compose version` **before** writing it.

### 10.1 Compose file syntax
Every attachable key has a short colon-separated string and a long mapping; short = terse, long carries fields short can't. One form per key, never both.

| Key | Short | Long keys |
| --- | --- | --- |
| `ports` | `"127.0.0.1:8080:80"` | `target` `published` `host_ip` `protocol` `app_protocol` `mode` `name` |
| `volumes` | `db-data:/var/lib/data:ro` | `type` `source` `target` `read_only` `bind` `volume` `tmpfs` `image` `consistency` |
| `environment` | `- KEY=value` | `KEY: value` |
| `depends_on` | `- db` | `condition` `restart` `required` |
| `configs` / `secrets` | `- my-cert` | `source` `target` `uid` `gid` `mode` |

- **`ports` is forbidden here (§4)** — the row is spec reference, kept to recognise/strip legacy entries. Old-file facts: short form `[HOST:]CONTAINER[/PROTOCOL]`, `HOST` = `[IP:](port|range)`; omitted host IP binds `0.0.0.0`; unquoted `8000:8000` = a YAML base-60 float.
- **Interpolation (spec)** — `${VAR}`/`$VAR`; `${VAR:-default}` (unset *or* empty), `${VAR-default}` (unset only), `${VAR:?err}`; nestable `${VAR:-${FOO:-bar}}`; `$$` emits a literal `$`. Unresolvable with no default → warning, empty. Applies to **values, not keys** — a `labels`/`environment` key interpolates only in the `KEY=value` string form.
- **Interpolation here is governed by §1.1**: bare `${VAR}` or bare `${VAR:?}` only. The spec's `:-`/`-`/`:?message`/`${VAR:-}` are not permission — a fallback substitutes an unset value, a message is prose. Don't cite the spec against §1.1.
- **Bytes** `{amount}{unit}`: `b`, `k`/`kb`, `m`/`mb`, `g`/`gb` — no `t`. **Durations** combinable without separator: `us`, `ms`, `s`, `m`, `h` → `1m30s`, `1h5m30s20ms`. Both cover healthcheck durations, `deploy.resources.memory`, `tmpfs size=`.
- **Traps** — `environment` booleans quoted (`SHOW: "true"`) or YAML makes `True`/`False`; `healthcheck.test` list starts `NONE`/`CMD`/`CMD-SHELL`, a bare string *is* `CMD-SHELL`; volume **short** syntax silently creates the host directory when absent (long `bind.create_host_path: false` prevents); relative host paths resolve against a local runtime only; `environment` beats `env_file`; `depends_on` conditions exactly `service_started`/`service_healthy`/`service_completed_successfully`; an `external: true` top-level volume carries **only** `name`.
- **Anchors resolve before interpolation** — an anchor/alias name can never be built from a variable.
- Sources: compose-spec/compose-spec `spec.md` (whole — all 96 sections, per-key minimum-version badges); docs.docker.com/reference/compose-file/ + `version-and-name`/`services`/`deploy`/`build`/`configurations`; github.com/docker/compose/releases. Re-verified 2026-10-03; raw pages cached under `.firecrawl/compose_spec/`.
