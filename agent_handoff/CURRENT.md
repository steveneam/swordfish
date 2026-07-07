# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 20:15 +10:00 (Bucket 4 — agent-side COMPLETE, founder-touch items pending)_

## State

**Bucket 4 built and verified through the Dokploy MCP — the AI-operability test
passed on every operation it needed** (create project/services/domains, inline
compose as source-of-truth, env save, deploy/redeploy, container+log reads,
domain middleware attach — zero SSH, zero UI). Full operating detail:
`runbooks/dogfood.md`.

- **Standing items cleared:** Renovate socket-proxy v0.4.2 merged + `edge-apply`
  green (idempotent, posture re-asserted). NOTE: Renovate cut a stale
  `renovate/traefik-3.x` branch (3.6.7→3.7.6) but no PR yet — handle by the
  edge protocol when it opens.
- **hello image:** CI→GHCR green (`hello-build.yml`): scratch, non-root,
  self-probing HEALTHCHECK, smoke-tested on the runner pre-push.
  `ghcr.io/steveneam/swordfish-hello:sha-f57702fe3ce5@sha256:c1f4823d...504c1996`
  (full digest in run 28856430785 summary). **Not deployed — needs the PAT below.**
- **Uptime Kuma 2.4.0** live at `status.swordfish.cfd` (Dokploy compose, tracked
  in `compose/status/`). Bootstrapped ENTIRELY via its socket.io API
  (`provisioning/kuma/bootstrap.py`, idempotency-proven): admin `swordfish`,
  ntfy notification, push monitor `swordfish-syd1-backup` + HTTP monitors for
  deploy/metrics/hello. hello monitor sits DOWN until hello deploys — expected.
- **Dead-man is now DUAL and proven by a real backup** (backups-apply run
  28857516067, 09:55 UTC): `hc-ping.sh` → healthchecks.io + Kuma push
  (`KUMA_PUSH_URL` repo secret → `/etc/resticprofile/kuma-url`); Kuma beat
  `backup-ok` recorded. Kuma/Beszel SQLite state rides the nightly set via
  `20-dogfood-sqlite-dumps` (host sqlite3 `.backup`; raw volumes stay out).
- **Beszel 0.18.7** live at `metrics.swordfish.cfd` (`compose/metrics/`):
  agent behind its OWN socket-proxy (raw socket never in an app container —
  now a standing assertion), no host network, syd1 reporting up
  (`provisioning/beszel/bootstrap.py`).
- **Rate limit:** `swordfish-ratelimit` (25 avg/50 burst) in the tracked edge
  hardening file, attached to status+metrics routers via MCP. Verified:
  hammer → 44×429 on status., **deploy. exempt** (80×200) by design.
- **Posture: 60/60 assertions green** (hardening-smoke run 28857849924) — +10
  Bucket-4 checks incl. the box-wide socket invariant and live route probes.
- RAM watch-item: ~71% used with all stacks idle → Bucket-5 resize input.

## Founder actions needed (each unblocks the next step)

1. **GHCR pull credential** for hello (repo is private → package is private):
   create a PAT with **read:packages** only and put it in `.env` as
   `GHCR_PULL_TOKEN=...` — agent wires it into Dokploy as a registry + deploys
   hello (`runbooks/dogfood.md` has the exact procedure). Alternative if you
   prefer zero standing secrets: make the `swordfish-hello` package public
   (publishes a steveneam↔swordfish link — your call).
2. **ntfy:** install the ntfy app on the phone, subscribe to the topic in
   `inventory/secrets/ntfy-topic.txt` — then the agent test-fires an alert.
3. **UptimeRobot** (off-infra witness #2, CHARTER decision 8): create the free
   account; either add an HTTPS monitor on `status.swordfish.cfd` +
   `deploy.swordfish.cfd` yourself, or drop `UPTIMEROBOT_API_KEY=...` in
   `.env` and the agent scripts it (preferred — becomes a ratchet).
4. **Password manager:** save `inventory/secrets/kuma-admin.password` (user
   `swordfish`) + `beszel-admin.password` (user `ops@swordfish.cfd`).

## Standing

- **Tonight 15:00 UTC**: first natural backup-timer fire — confirm tomorrow:
  healthchecks "Last Ping" AND Kuma push beat both fresh (~01:00 AEST stamps).
- Traefik 3.7.6 Renovate PR (when it opens): edge pin bump = edge-apply protocol.

## Next

Founder items above → hello deploy via MCP + attach ratelimit + kuma monitor
flips UP → alert test-fire (ntfy + UptimeRobot) → **Bucket-4 CHECKPOINT**:
definition-of-done checklist + record the Dokploy-MCP verdict (evidence so far
says KEEP: every needed operation worked first-try over the MCP; quirks
documented in `runbooks/dogfood.md`) + the Bucket-4/5 fork decisions
(box-path resize-vs-migrate, Hermes pilot go/no-go).

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network) · zero guarded tokens in tracked files, extends to public
names (CT logs) · backups before workloads — satisfied, now covering the
dogfood state too · every spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
