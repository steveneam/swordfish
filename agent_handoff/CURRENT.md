# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 15:55 +10:00 (Bucket 2 main build + founder gate session)_

## Gate progress (live update, same session)

Founder gate is **9/10 closed**: admin registered (race won — signup, not login),
green lock confirmed on phone (mobile data; corp FortiGuard MITM-blocks the new
domain from the office — recategorization request = founder to-do), Server Domain
set, API key generated → `.env` `DOKPLOY_API_KEY`, **Dokploy MCP registered**
(local scope, `~/.claude.json` — user-private) and its process connects.
**Remaining:** one MCP tool call verified end-to-end — impossible from the corp
network (node rejects the Fortinet-resigned cert), needs hotspot or the
FortiGuard recategorization to land. Then flip Web Server HTTPS toggle via API.

Incident closed into ratchets: founder saved Server Domain with HTTPS toggle off
→ Dokploy deleted its own websecure router → UI 404 with no recovery path (3000
unpublished by design). Fixed live via converge (now **self-heals that route** —
invariant: control plane stays reachable over TLS) + new assertion `dokploy route
live (no 404)` → **40/40**. DO NOT re-save Settings → Web Server from the UI until
the HTTPS toggle is fixed via API. Lesson saved to agent memory: **agent
credential first, founder UI changes second.**

## State

**Bucket 2 BUILT, APPLIED, CI-VERIFIED on syd1** at `a7c886c` — stopped at the ⛔
founder gate (browser green-lock + Dokploy MCP), which is founder-action-only.
syd1 still carries NOTHING until Bucket-3 backups (invariant).

- Edge live: `swordfish-traefik` v3.6.7 + tecnativa/docker-socket-proxy 0.3.0
  (digest-pinned compose in `compose/edge/`; socket read-only, `CONTAINERS=1`,
  proxy on an internal-only network; 80/443 TCP the only published ports anywhere).
  TLS-ALPN Let's Encrypt; entrypoint-level HTTPS redirect + HSTS/security headers;
  modern-TLS options; JSON logs; no dashboard; no HTTP/3 (firewalls are TCP-only).
- Control plane live: **Dokploy v0.29.10 pinned** behind TLS at
  `deploy.swordfish.cfd` (A-record set via `set-a-record.ps1`; cert CI-verified:
  smoke's green-lock probe passes CA validation). Install **vendored** into
  `provisioning/host/phase3-edge.sh` (upstream install.sh is destructive on
  re-run — `swarm leave --force` — and needs 80/443 free; vendoring de-fangs it).
  **Port 3000 never published** — UI only via the TLS route. Dokploy's Traefik
  contract preserved (entrypoints web/websecure, resolver `letsencrypt`, dynamic
  dir `/etc/dokploy/traefik/dynamic`); our container deliberately NOT named
  `dokploy-traefik` (Dokploy force-removes that name). Rules: `runbooks/edge.md`.
- Live-hardware discoveries (all ratcheted into code/docs):
  **live-restore is swarm-incompatible** (daemon refuses swarm init → dropped from
  daemon.json everywhere); bare `[ ] &&` as a function's last line kills `set -e`
  converges; stock sshd fails ssh-audit → **sshd crypto floor** added
  (curve25519/sntrup kex, no NIST-curve/hmac-sha1) in phase2 + cloud-init + asserts.
- Verification: `edge-apply` green (converge + idempotency-no-op proof + wait +
  re-assert); `hardening-smoke` green — **39/39 assertions**, **ssh-audit
  [fail]-clean** (only warns: classical-curve kex, PQ kex is offered first),
  **TLS green-lock probe PASS**. Headroom on record in every smoke header:
  1308M used / 1962M total, 653M avail; swap 39M/6.3G — 2 GB tier holds.

## Next — ⛔ founder gate (Bucket-2 checkpoint), then Bucket 3

1. **FIRST + TIME-SENSITIVE: register the Dokploy admin** at
   `https://deploy.swordfish.cfd`. Registration is open-until-first-signup and the
   cert is now in CT logs (scanners probe fresh certs). If a LOGIN screen appears
   instead of signup, someone won the race → do not proceed; teardown + recreate
   (`docker service rm dokploy && docker volume rm dokploy dokploy-postgres` via a
   dispatch, then re-run `edge-apply`).
   Corp-network note: FortiGuard blocks the domain right now ("Newly Observed
   Domain") — use the phone/hotspot, or the block page's re-evaluate link.
2. Gate evidence: green lock in the browser ✓ → in Dokploy **Settings → Web
   Server: set Server Domain** = `deploy.swordfish.cfd` (Dokploy then owns the
   route file — handover is a no-op by design) → generate an **API key** →
   `claude mcp add dokploy --env DOKPLOY_URL=https://deploy.swordfish.cfd --env DOKPLOY_API_KEY=<key> -- npx -y @dokploy/mcp`
   → Dokploy MCP reachable from Claude Code = gate closed. **Never** use the UI's
   Traefik actions or LE-email field (`runbooks/edge.md`).
3. Then **Bucket 3 — backups BEFORE workloads** (invariant): B2 bucket + scoped
   key (founder: keys already in `.env`), resticprofile nightly, `/etc/dokploy` +
   Traefik config in the set, dead-man ping, **real restore drill**. Dokploy
   upgrades stay frozen until this lands.
4. Renovate digest-bump PRs may arrive — review/merge as they come.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network; FortiGuard MITMs new domains) · zero guarded tokens in tracked
files — extends to public names (CT logs) · backups before workloads (syd1
carries NOTHING until Bucket 3) · Projects are 1/2/3 only · every spend is an
Approval Gate · founder is the sole author (no AI attribution).

_All work is committed and pushed — it is safe to clear this session._
