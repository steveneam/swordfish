# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 16:30 +10:00 (Bucket 2 build + founder gate session)_

## State

**Bucket 2 COMPLETE — ⛔ gate CLOSED with the founder in the loop.** syd1 edge +
control plane live and CI-verified; box still carries NOTHING until Bucket-3
backups (invariant).

- Edge: `swordfish-traefik` v3.6.7 + socket-proxy 0.3.0 (`compose/edge/`,
  digest-pinned; socket ro `CONTAINERS=1`; 80/443 the only published ports).
  TLS-ALPN LE cert live at `deploy.swordfish.cfd`; HSTS/headers; JSON logs.
- Control plane: **Dokploy v0.29.10 pinned** (vendored install in
  `phase3-edge.sh`, no 3000 publish). Admin registered (founder, race won).
  Server Domain + **https=true + letsencrypt set via API** (assignDomainServer) —
  Web Server panel is safe again. **Dokploy MCP registered + verified
  end-to-end** (real `project-all` call → success over hotspot; corp network
  pending FortiGuard recategorization — founder to submit; MCP tools load
  natively next Claude Code session).
- Verification: `edge-apply` green (idempotency proof), `hardening-smoke` green —
  **40/40 assertions** (incl. new `dokploy route live (no 404)`), ssh-audit
  [fail]-clean, CA-valid green-lock probe. Headroom 1323M/1962M, 638M avail.
- Incident ratcheted: Server-Domain-save with HTTPS off deleted the websecure
  router → UI 404, no founder-side recovery (3000 unpublished by design). Fixed
  live; converge now **self-heals the route** (invariant: control plane stays
  reachable over TLS); assertion added. Memory saved: **agent credential first,
  founder UI changes second.**
- Other live discoveries (all in code/docs): live-restore ↔ swarm-mode conflict
  (dropped, why recorded); sshd crypto floor (ssh-audit gate); `[ ] &&` set -e
  footgun; FortiGuard MITMs new domains from the corp network (probe evidence:
  Fortinet-issued cert). Rules live in `runbooks/edge.md`.

## Next — Bucket 3: backups BEFORE workloads (invariant)

1. B2: create `swordfish-syd1-backups` bucket (US West) + bucket-scoped key
   (account keys already in `.env`); ~30-day versioning.
2. resticprofile nightly (tracked YAML): retention 7d/4w/6m, weekly
   `check --read-data-subset=10%`, prune; **`/etc/dokploy` + Traefik config in
   the set**; pre-backup hooks pattern for future stateful workloads.
3. Dead-man switch: success-only ping → healthchecks.io now (off-infra witness);
   Uptime Kuma push monitor joins in Bucket 4.
4. **Real restore drill** into scratch, RTO/RPO in `runbooks/` — starts the
   monthly-pass cadence. Dokploy upgrades stay frozen until this bucket lands.
5. Standing: Renovate digest PRs (review as they come) · FortiGuard
   recategorization **submitted 2026-07-07** via the public fortiguard.com form
   (Fortinet-only, company not involved; expect ~1-2 days) — note the office
   FortiGate MITMs TLS regardless, so control-plane UI/MCP work stays on
   phone/hotspot as the standing posture (office = eyes-limited: git/CI/Vultr
   console only; never send the API key through the corp proxy) · vault
   research-sync if still pending.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network; FortiGuard MITMs new domains — recategorization pending) ·
zero guarded tokens in tracked files, extends to public names (CT logs) ·
backups before workloads (syd1 carries NOTHING until Bucket 3) · Projects are
1/2/3 only · every spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
