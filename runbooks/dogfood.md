# Dogfood workloads (Bucket 4)

Uptime Kuma (`status.`) + Beszel (`metrics.`) + hello (`hello.`) on syd1 —
Dokploy project **swordfish**, deployed and operated **through the Dokploy MCP
from Claude Code** (the AI-operability test, CHARTER pinned decision 10).

## Source of truth + apply channel

| service | tracked file | Dokploy composeId | live at |
|---|---|---|---|
| status (Uptime Kuma 2.4.0-rootless) | `compose/status/compose.yaml` | `5h4OEMKIBVnmSqzMy_TtH` | https://status.swordfish.cfd |
| metrics (Beszel 0.18.7 hub+agent+socket-proxy) | `compose/metrics/compose.yaml` | `koQq7S1xUJgfR7yQEZ4ij` | https://metrics.swordfish.cfd |
| hello (deploy receipt, `apps/hello/`) | Dokploy application, applicationId `wtPRsmmiQ_yJRVKTjCXuq` (appName `swordfish-hello-vfvt10`) | — | https://hello.swordfish.cfd |

Change protocol: edit the tracked compose → `compose-update` (composeFile) →
`compose-deploy` via MCP. Never edit in the Dokploy UI — the repo copy wins at
the next apply. In-app config (Kuma monitors, Beszel systems) converges via
the **idempotent bootstrap scripts** — the scripted channel, re-run any time:

```
python provisioning/kuma/bootstrap.py     # socket.io API (no REST admin API)
python provisioning/beszel/bootstrap.py   # PocketBase REST
```

Both read/write creds under `inventory/secrets/` (map: `runbooks/backup-restore.md`).
Their state is in the nightly backup set as SQLite dumps (`20-dogfood-sqlite-dumps`).

## Dokploy MCP landmines (learned 2026-07-07, v0.29.10)

- `compose-create` defaults `sourceType` to **github** even when you pass
  `composeFile` — immediately `compose-update` it to `raw` or deploys fail.
- `appName` gets a random suffix at create and is **immutable after** —
  container/volume names carry it (recorded in each compose header).
- Compose domains are implemented as **injected Traefik labels** (see
  `compose-getConvertedCompose`), not dynamic files — a domain change needs a
  redeploy to take effect; Traefik sees the labels via the edge socket-proxy.
- Create domains **before** the first deploy and the cert lands with it
  (TLS-ALPN takes a minute or two; `sniStrict` resets the handshake until then).

## Rate limiting (public routers only — never the control plane)

`swordfish-ratelimit` (25 rps avg / 50 burst per client IP) is defined in
`compose/edge/traefik/dynamic/50-swordfish-hardening.yml` (tracked; lands via
`edge-apply`) and attached per-domain via the MCP `domain-update`
`middlewares: ["swordfish-ratelimit@file"]` + redeploy. Attached: status,
metrics (+ hello at its deploy). **`deploy.` stays exempt** — an attacker
tripping a limit must not lock the founder out of the recovery path
(Checkpoint-2 amendment 4). Verified 2026-07-07: 80-request hammer → 44×429
on status., 80×200 on deploy.

## hello image updates (deployed 2026-07-07; the digest pin lives in Dokploy, not the repo)

Image: CI-built by `hello-build.yml` → `ghcr.io/steveneam/swordfish-hello`
(private; new digest in each run's step summary). The box pulls with the
founder's `read:packages` PAT (`GHCR_PULL_TOKEN` in `.env`; stored in
Dokploy's registry credential store, which the backups cover). **Renovate
cannot see this pin** — updates are agent-operated: new CI build →
`application-saveDockerProvider` with the new digest-pinned ref →
`application-deploy`. The page's build SHA + Kuma's UP/DOWN alerts are the
deploy receipt.

## Alert path (all legs verified 2026-07-07)

- **Kuma → ntfy.sh topic** (`inventory/secrets/ntfy-topic.txt`) → founder
  phone. The topic string is the only credential. Verified live: founder
  received hello's DOWN alert on subscribe + its UP on deploy.
- **UptimeRobot** (`provisioning/uptimerobot/bootstrap.py`, idempotent):
  5-min HTTP checks on `status.` + `deploy.` → email. Second off-infra
  witness; healthchecks.io remains the dead-man witness for backups.
