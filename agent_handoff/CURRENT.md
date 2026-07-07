# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 18:27 +10:00 (platform-parity research & planning session)_

## State

**Bucket 2 COMPLETE (gate closed, 4c28ed1). Bucket 3 NOT started — this session was
founder-directed research/planning only.** Box still carries NOTHING until Bucket-3
backups (invariant).

New artifact: **`research/2026-07-07-platform-parity-plan.md`** — the PaaS→VPS parity
map (Vercel / Render / Supabase / AWS → OSS-on-box equivalents) + target architecture.
Headlines:

- **Gaps to close for parity: 4** — AI gateway (Bifrost, Apache-2.0, recommended; LiteLLM
  /Portkey alternatives; Vercel AI Gateway is host-independent so apps can swap by env
  var later), object storage (R2/B2 managed; SeaweedFS if sovereignty; MinIO is dead),
  bigger box, DuckDB/Parquet analytics lane (pg_duckdb 1.0 + Parquet-on-R2; Bucket 7).
  Everything else (deploys, previews, cron, workers, volumes, TLS) Dokploy+Traefik
  already covers.
- **Founder spec >8 GB / >100 GB / AU latency fits the $30 ceiling:** BinaryLane SYD
  4vCPU/8GB/100GB NVMe ≈ AU$39.20 ex GST (≈US$26). Bucket-5 fork flagged: resize-in-place
  (Vultr US$40, ceiling bump) vs **graduate-by-migrating to BinaryLane (= portability
  drill)**. OVH SYD has a 10 Mbps post-quota cap (trap). Hetzner stays the Bucket-7
  egress candidate.
- Supabase: RLS is plain Postgres — à-la-carte on-box (Postgres 17 ± PostgREST ± Better
  Auth) for new workloads; Project 1's managed plane untouched (invariant); full
  self-host Supabase = 16 GB box + own gated bucket only.
- Atlassian edge notes (founder-supplied, local/untracked): adopt forward-auth choke
  point, Traefik rate-limit middleware, broker-pattern validation of Dokploy MCP,
  preview-deploy canaries; reject Envoy/anycast/autoscale at our scale.
- Portability: provider-specific surface = 3 calls (create-box/firewall/DNS) → keep
  `provisioning/<provider>/` adapter seam; migration = provision + converge + restic
  restore + DNS flip; the monthly restore drill IS the migration rehearsal.
- Terminal: SSH + Dokploy web terminal (443) + CI-as-hands. **Pi (pi.dev, MIT)** assessed
  as a strong harness candidate for the post-Bucket-5 on-box agent pilot (would call our
  own gateway; budget-capped key; E0→E1 autonomy) — not on the 2 GB box.
- 4 open founder questions at §10 of the research doc (Bucket-5 path · gateway posture ·
  Supabase stance + which project drives the >100 GB · forward-auth yes/no).

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
5. Opportunistic while touching files: make the `provisioning/<provider>/` adapter
   boundary visible (file-moves only, no behavior change).
6. Standing: Renovate digest PRs (review as they come) · FortiGuard recategorization
   submitted 2026-07-07 (~1-2 days; office stays eyes-limited regardless — control-plane
   UI/MCP on phone/hotspot only; never send the API key through the corp proxy) · vault
   research-sync if still pending.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network; FortiGuard MITMs new domains) · zero guarded tokens in tracked
files, extends to public names (CT logs) · backups before workloads (syd1 carries
NOTHING until Bucket 3) · Projects are 1/2/3 only · every spend is an Approval
Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
