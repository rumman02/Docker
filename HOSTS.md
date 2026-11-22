# Per-host configuration

One `compose.yaml` per stack everywhere; host-specific values live only in each stack's `.env` — never in compose files.

## Docker engine

| | Linux device | Mac |
| --- | --- | --- |
| Engine | `<engine>` package (systemd service) | `<engine>.app` (bundled Linux VM) |
| Docker API socket | `/run/<engine>/docker.sock` | `~/.<engine>/run/docker.sock` |
| CLI | system `<engine>` / `docker` | links in `~/.<engine>/bin` |

## `.env` differences (network stack)

| Key | Linux | Mac |
| --- | --- | --- |
| `SOCKET_PROXY_DOCKER_SOCKET` | `/run/<engine>/docker.sock` | `~/.<engine>/run/docker.sock` |
| `SOCKET_PROXY_USER` | `65534:969` (socket group `<engine>`) | `65534:0` (socket presents `root:root` in the VM) |
| `TAILSCALE_IP` | this host's live Tailscale IPv4 | this host's live Tailscale IPv4 |

`TAILSCALE_IP` must match the host's current registration — a fresh Tailscale login gets a new name and IP, so re-check `tailscale ip -4` after any re-auth and update `.env`.

`net_anchor` needs no per-host changes — runs as-is on both hosts.
