# Dogfood workloads (Bucket 4; replayed on syd2 at Bucket 5)

Uptime Kuma (`status.`) + Beszel (`metrics.`) + hello (`hello.`) — Dokploy
project **swordfish**, first deployed on syd1 **through the Dokploy MCP from
Claude Code** (the AI-operability test, CHARTER pinned decision 10), replayed
on syd2 2026-07-08 **through the raw Dokploy REST API** (`x-api-key` header;
same procedures, MCP tool name ↔ `router.procedure` endpoint 1:1 — the
portability proof for the integration-surface ruling).

## Source of truth + apply channel

syd2 IDs (current box; syd1 rows below it retire at cutover):

| service | tracked file | Dokploy id (syd2) | live at |
|---|---|---|---|
| status (Uptime Kuma 2.4.0-rootless) | `compose/status/compose.yaml` | composeId `LozRPFJ8LCLK88hvc7ke5` | status.swordfish.cfd (pre-cutover: status2.) |
| metrics (Beszel 0.18.7 hub+agent+socket-proxy) | `compose/metrics/compose.yaml` | composeId `1PiSAb1dg6TiRGw9X1C4Q` | metrics.swordfish.cfd (pre-cutover: metrics2.) |
| hello (deploy receipt, `apps/hello/`) | Dokploy application, applicationId `-a2FMiW1gq30KstVf37w6` (appName `swordfish-hello-ksv6id`) | — | hello.swordfish.cfd |

syd1 (frozen, retires at cutover): status `5h4OEMKIBVnmSqzMy_TtH` · metrics
`koQq7S1xUJgfR7yQEZ4ij` · hello `wtPRsmmiQ_yJRVKTjCXuq` (`swordfish-hello-vfvt10`).

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
  **Pass an `appName` base at `application.create`** (learned syd2 replay,
  2026-07-08): omit it and Dokploy generates a fully random name
  (`app-navigate-1080p-...`) that breaks the `swordfish-hello` container
  assertion; pass `appName: swordfish-hello` and Dokploy keeps the base +
  adds its suffix. The posture assertion enforces the convention.
- Compose domains are implemented as **injected Traefik labels** (see
  `compose-getConvertedCompose`), not dynamic files — a domain change needs a
  redeploy to take effect; Traefik sees the labels via the edge socket-proxy.
- Create domains **before** the first deploy and the cert lands with it
  (TLS-ALPN takes a minute or two; `sniStrict` resets the handshake until then).
- `application.saveEnvironment` requires `buildArgs` + `buildSecrets` +
  `createEnvFile` in the body even when unchanged — fetch first, send back
  (learned thalon wiring 2026-07-13; same session: `registry.create` requires
  `imagePrefix`, `saveDockerProvider` takes inline username/password).
- **Image bumps for CI: use `application.update` `{applicationId, dockerImage}`**,
  not `saveDockerProvider` — update leaves the stored pull credential
  untouched, so a tenant CI never needs to hold the GHCR PAT.
- `user.assignPermissions` keys on the **user id**, NOT the member-row id —
  and it answers **200 silently for an unknown id**. Always read the member
  back after assigning (tenant-credential.sh does).
- API keys minted via `user.createApiKey` default to better-auth's
  **rateLimitEnabled: 10 requests per DAY**. A rate-limited key fails session
  validation, so every call returns a bare `{"message":"Unauthorized"}` that
  reads exactly like a permission bug. Pass `rateLimitEnabled: false`.
- Member write authz is statement-based (`packages/server/src/lib/access-control.ts`):
  `application.update` gates on `service:create` (the `canCreateServices`
  flag); `application.deploy` rides the base member role. The full scoped-
  credential recipe is `provisioning/dokploy/tenant-credential.sh`.
- Dokploy's per-app basicauth middleware is generated with
  **`removeHeader: true`** (app never sees the Authorization header). Staging
  needs `false` (one pair, two gates — thalon staging-verify finding 2).
  The flag survives deploy/redeploy but **security CRUD regenerates it** —
  `provisioning/thalon/staging-assert.sh` converges it back and asserts the
  whole staging posture.

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
