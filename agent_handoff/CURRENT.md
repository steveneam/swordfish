# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 18:41 +10:00 (platform-parity research → Checkpoint-2 amendments)_

## State

**Bucket 2 COMPLETE (gate closed). Bucket 3 NOT started.** Box carries NOTHING until
Bucket-3 backups (invariant). This session: parity research + founder Q&A →
**Checkpoint-2 amendments landed in CHARTER.md** (canonical), mirrored in
`inventory/decisions.md`; full findings in `research/2026-07-07-platform-parity-plan.md`
(§10 marked resolved).

The six Checkpoint-2 calls (short form — charter is canonical):

1. AI gateway: projects stay on Vercel AI Gateway until self-hosted **Bifrost**
   (Apache-2.0) is deployed + drilled (Bucket-5 era); swap = base-URL env var.
2. Bucket-5 box-path fork stays open: resize-in-place (Vultr 8GB US$40) vs
   graduate-by-migrating (BinaryLane SYD 8GB/100GB ≈US$26 = portability drill).
   Decide at the Bucket-4/5 checkpoint.
3. Disk want is portfolio-aggregate >100GB → per-workload homes (R2 artifacts ·
   B2 backups · per-box volumes for reference data), never one giant disk.
4. Forward-auth SSO: **not before box #2** (reachability invariant; must exempt
   Dokploy API/MCP routes); rate-limit middleware Bucket 4 on public routers only.
5. Analytics lane pinned: pg_duckdb 1.0 + Parquet-on-R2 at Bucket 7.
6. Bucket-3 opportunistic: surface `provisioning/<provider>/` adapter seam.

## Next — Bucket 3: backups BEFORE workloads (invariant, unchanged)

1. B2: create `swordfish-syd1-backups` bucket (US West) + bucket-scoped key
   (account keys already in `.env`); ~30-day versioning.
2. resticprofile nightly (tracked YAML): retention 7d/4w/6m, weekly
   `check --read-data-subset=10%`, prune; **`/etc/dokploy` + Traefik config in
   the set**; pre-backup hooks pattern for future stateful workloads.
3. Dead-man switch: success-only ping → healthchecks.io now (off-infra witness);
   Uptime Kuma push monitor joins in Bucket 4.
4. **Real restore drill** into scratch, RTO/RPO in `runbooks/` — starts the
   monthly-pass cadence. Dokploy upgrades stay frozen until this bucket lands.
5. Opportunistic: `provisioning/<provider>/` adapter seam (file moves only).
6. Standing: Renovate digest PRs (review as they come) · FortiGuard
   recategorization submitted 2026-07-07 (~1-2 days; office stays eyes-limited
   regardless — control-plane UI/MCP on phone/hotspot only; never send the API
   key through the corp proxy) · vault research-sync if still pending.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network; FortiGuard MITMs new domains) · zero guarded tokens in tracked
files, extends to public names (CT logs) · backups before workloads (syd1 carries
NOTHING until Bucket 3) · Projects are 1/2/3 only · every spend is an Approval
Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
