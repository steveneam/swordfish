# Dogfood workloads (Bucket 4)

Uptime Kuma (`status.`) + Beszel (`metrics.`) + hello (`hello.`) on syd1 —
Dokploy project **swordfish**, deployed and operated **through the Dokploy MCP
from Claude Code** (the AI-operability test, CHARTER pinned decision 10).

## Source of truth + apply channel

| service | tracked file | Dokploy composeId | live at |
|---|---|---|---|
| status (Uptime Kuma 2.4.0-rootless) | `compose/status/compose.yaml` | `5h4OEMKIBVnmSqzMy_TtH` | https://status.swordfish.cfd |
| metrics (Beszel 0.18.7 hub+agent+socket-proxy) | `compose/metrics/compose.yaml` | `koQq7S1xUJgfR7yQEZ4ij` | https://metrics.swordfish.cfd |
| hello (deploy receipt, `apps/hello/`) | Dokploy application (pending GHCR PAT) | — | https://hello.swordfish.cfd |

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

## hello deploy (the one open Bucket-4 step; needs founder GHCR PAT)

Image: CI-built by `hello-build.yml` → `ghcr.io/steveneam/swordfish-hello`
(private; digest in the run's step summary). With a `read:packages` PAT:
1. MCP `registry-create` (ghcr.io, username steveneam, PAT as password), or
   make the package public and skip credentials (founder's call).
2. MCP `application-create` in project swordfish → `application-saveDockerProvider`
   with the digest-pinned image → `domain-create` hello.swordfish.cfd port 8080
   (+ ratelimit middleware) → `application-deploy`.
3. Kuma monitor `hello (deploy receipt)` already exists and flips UP on deploy;
   page shows the built git SHA = deploy receipt.

## Alert path

Kuma → ntfy.sh topic (`inventory/secrets/ntfy-topic.txt`) → founder phone
(subscribe in the ntfy app; the topic string is the only credential).
Test-fire after subscribing: pause/resume a monitor, or Kuma UI → the
notification's Test button. UptimeRobot external check = still to wire
(founder account); healthchecks.io remains the off-infra dead-man witness.
