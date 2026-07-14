# Capacity + data-platform plan — 2026-07-13 (post-cutover)

_Founder asked (same evening as the cutover): next phases · next VPS tier ·
Supabase-equivalent RLS database ≥100 GB · moving Project 1's ~60 GB (and
growing) Render persistent disk to a box. Facts below pulled live from the
BinaryLane API + fleet telemetry this session. Decisions here are proposals —
every purchase/resize is an Approval Gate._

## Where we stand (verified)

- syd2 (std-4vcpu: 4 vCPU / 8 GB / 100 GB, AUD 39.20): **28% RAM, 14% disk,
  ~1% CPU** with thalon staging + all dogfood live. No pressure today —
  capacity buys are for what's COMING, not what's burning.
- Cash run-rate: syd2 + syd4 ≈ AUD 78.40 ≈ US$52/mo; syd1 + syd3 ride Vultr
  credit; syd1 leaves at soak end.
- BinaryLane has **no block storage product** (API: no volumes endpoint;
  disk is per-plan). More disk = plan resize (grow-only) or a second box.
  Vultr (retained fallback account) does sell Sydney block storage —
  price-check at gate time if we ever want detachable volumes.

## BinaryLane SYD ladder (live 2026-07-13, ALL in stock — incl. the HDD
plans that were out of stock at Bucket-5, availability datapoint)

| slug | RAM / vCPU / NVMe | AUD/mo | note |
|---|---|---|---|
| std-4vcpu | 8 GB / 4 / 100 GB | 39.20 | syd2 + syd4 today |
| **std-6vcpu** | **16 GB / 6 / 180 GB** | **78.40** | the next tier — exactly double |
| std-8vcpu | 32 GB / 8 / 340 GB | 156.80 | one-box-everything class |
| cpu-8thr | 16 GB / 8 / 300 GB | 144.00 | compute-optimised, more disk than std-6 |
| ded-e2136-400gb | 32 GB / 12 / 400 GB | 175.00 | dedicated cores |
| hdd-1000gb | 2 GB / 1 / **1 TB HDD** | 30.00 | bulk/cold store only — HDD, weak CPU |

## The three asks, answered

### 1. Next VPS tier
**std-6vcpu: 16 GB / 6 vCPU / 180 GB NVMe at AUD 78.40/mo** — a clean double
of syd2. BinaryLane supports in-place resize (grow-only disk; brief
downtime), so the upgrade path does NOT need another parallel-run — but it
is a spend gate, and today's telemetry says no urgency until thalon render
offload / Project 1 assets actually land. Recommendation: **resize at the
moment a real workload needs it, not before.**

### 2. Supabase-equivalent RLS database (≥100 GB)
RLS is a **native PostgreSQL feature** — "Supabase" adds managed hosting +
auth (GoTrue) + auto-API (PostgREST) + realtime + storage on top.

- **If the DB is Project 1's compliance-bound data plane: the charter
  keep-managed invariant says it STAYS on a managed service** (managed
  Supabase has a Sydney region on AWS ap-southeast-2). Self-hosting it on a
  box is the one move the charter forbids ("never migrate a
  clinical/stateful data plane"). Revisiting that is a re-charter decision,
  not an ops task.
- **If it's for Thalon or another non-compliance workload:** self-hosted
  **plain Postgres + RLS via Dokploy** is easy and fits our proven pattern
  (digest-pinned image, compose in-repo, restic to B2). The full self-hosted
  Supabase stack (~10 services: Kong, GoTrue, PostgREST, Realtime, Storage,
  Studio…) is only worth its upgrade burden if the auth/auto-API layers are
  genuinely used.
- **At 100 GB+ the backup plane changes:** nightly `pg_dump` fulls (fine at
  dogfood scale) become impractical — the ratchet is **wal-g or pgBackRest
  incremental/WAL archiving to B2**, with a restore drill BEFORE workloads
  (backups-before-workloads is an invariant). B2 storage cost is trivial
  (~US$6/TB/mo); the engineering is the drill, not the bill.

### 3. Project 1's Render persistent disk (~60 GB, growing)
Render persistent disks cost **US$0.25/GB/mo** (60 GB ≈ US$15/mo, and it
scales linearly) — this is exactly the charter's "mispriced data-disk" case
and pre-approved in principle for moving. Two very different destinations:

- **If the assets are HTTP-served static files:** Backblaze B2 (+ Cloudflare
  in front, free egress via their alliance) ≈ **US$0.36/mo for 60 GB** —
  ~40× cheaper than Render and needs NO box disk at all.
- **If the app needs POSIX filesystem access:** box NVMe — which drives the
  sizing below.
- Transfer path either way: a job inside the Render service pushes to
  B2/box over 443 (Render disks have no external export); checksum-verified;
  parallel-run then flip, same protocol as the cutover. Project 1's agent
  does the app side (separation of duties); we prepare + back up the landing
  zone first.

## Sizing options (if both the 60 GB assets AND a 100 GB+ DB come to boxes)

| option | shape | cash Δ | total infra cash | notes |
|---|---|---|---|---|
| A | resize syd2 → std-6vcpu | +39.20 | ≈ AUD 117.60 (~US$78) | 16 GB/180 GB — fits assets OR the DB, tight for both + growth |
| **B** | keep syd2 + **new std-6vcpu data box** | +78.40 | ≈ AUD 156.80 (~US$104) | data plane isolated (blast radius, independent resize); my recommendation if the DB self-hosts |
| C | replace syd2 with std-8vcpu | +117.60 | ≈ AUD 196 (~US$130) | one big box; another parallel-run migration |
| D | assets→B2/CDN + DB stays managed | ~+0 | ≈ AUD 78.40 (~US$52) | cheapest; valid whenever assets are HTTP-served and the DB is compliance-bound anyway |

## Proposed phases

1. **Soak close-out (≈2026-07-16):** monitors green → retire `*2` records →
   syd1 destroy-vs-warm-fallback gate.
2. **Post-cutover ops week:** syd3/syd4 Kuma push dead-man legs · key
   rotation (environment now proven) · traefik 3.7.7 · Dokploy notifications
   · morning briefing v1 (real Kuma/Beszel/healthchecks metrics) · Renovate
   PR #4 · ntfy retirement audit · healthchecks→Telegram · port-map call.
3. **Capacity + data platform (gated on the founder answers below):** spend
   gate → provision/resize → restic/wal-g + restore drill on the new volume
   → asset migration runbook + execution → DB platform if self-host chosen.
4. **Tenant onboarding:** thalon render offload · Project 1/2 tenant packs
   via `tenant-credential.sh` (app side stays with their agents).
5. **Structural debt + re-charter checkpoint:** Ansible/dev-sec promotion
   (charter ladder says box #2+; we're at bash × 4 boxes), OpenTofu at the
   next box create, and the cash-ceiling re-read (US$52 → up to ~US$104)
   belongs at a charter checkpoint, not buried in an ops commit.

## Founder answers (same evening, 2026-07-13 ~23:20)

1. The ≥100 GB RLS DB is **Project 1's → stays on managed Supabase for now**
   (matches the keep-managed invariant; option D economics apply).
2. **Yes — a self-hosted Postgres for Thalon + Project 2** is wanted. Since
   there's no launch/traffic yet, it lands on the EXISTING syd2 at **zero new
   spend** (85 GB disk free, 72% RAM free): one Postgres 17 service via
   Dokploy, per-tenant databases + roles (RLS native), credentials handed off
   per tenant-credential pattern, pg_dump→restic chain now, graduate to
   wal-g/pgBackRest when size demands. Backups + restore drill BEFORE any
   real tenant data (invariant).
3. Render-disk access pattern: founder doesn't recall — **deferred**; decide
   B2+CDN vs box NVMe when Project 1's agent can check how the app reads it.
   **SUPERSEDED same evening** — investigated below: the app reads them off
   the filesystem (absolute runtime asset paths under the disk mount, set in
   their `render.yaml`), so box NVMe it is; B2+CDN does not apply.
4. Growth: pre-launch, no traffic — but **the driver is cost reduction, and
   the Render bill is live**, so the resize is justified by SAVINGS, not
   capacity (see the Render section: net −US$14/mo).
5. Clarified in chat: the US$78 / US$104 figures are **all-in monthly cash
   totals for the whole fleet** (every box we pay cash for, disk bundled) —
   current total is ~US$52. Option A (resize to 16 GB/180 GB → ~US$78) is
   now RECOMMENDED because cancelling Render (−US$40) more than covers it.

## Project 1's Render disk — INVESTIGATED 2026-07-13 (founder: "look at the
## project 1 folder and see which one it is")

**Which one:** Render **persistent disk** (there is no "disk instance" in
Render's product line), mounted at a fixed path and holding the project's
bio-reference asset tree. Compute is the **Render Standard plan (2 GB / 1 CPU
≈ US$25/mo)**; the disk adds **US$0.25/GB/mo** (~60 GB ≈ US$15/mo) →
**≈ US$40/mo total** to cancel.

**⚠️ The load-bearing finding: the Render disk is a CACHE, not the source of
truth — cancelling Render loses NOTHING.**

- The disk was *seeded*, not authored: Project 1's own progress log
  (2026-06-21) records the seed via their admin materialization endpoint —
  **ready 7/7, 0 failed, all sha256 verified**, ≈40.8 GB: dbsnp 29.55 GB
  (+tbi), phylop 9.87 GB, repeatmasker 701 MB, clingen 528 MB, clinvar
  vcf+tbi.
- The **source of truth is their private Supabase Storage source-asset
  bucket (~38 GB)** — and the underlying corpora (dbSNP, ClinVar, phyloP,
  RepeatMasker, ClinGen) are **public reference datasets**, re-downloadable
  from NCBI/UCSC in the worst case. The derived artifacts (repeatmasker
  compact index, clingen sqlite) are generated + manifested.
- So there is **no rescue deadline**: the same proven, checksum-verifying
  materialization run that seeded Render re-seeds a box disk. Cancel Render
  whenever; nothing is stranded.
- **Charter check: this data MAY move.** These are public reference assets,
  NOT the compliance-bound clinical data plane (that's their Supabase
  Postgres + auth, which stays managed). Moving reference assets + app
  compute off a mispriced disk is exactly what the charter blesses.

**Sizing: ~40.8 GB of assets (growing — hg38.2bit / Protein View queued).**
syd2 today is 100 GB with ~85 GB free, so the assets *technically* fit at
zero spend — but that leaves ~44 GB for Postgres + Docker churn + thalon +
asset growth, which is a squeeze with no room to be wrong.

**Recommendation (the Render money funds it):**
**resize syd2 → std-6vcpu (16 GB / 6 vCPU / 180 GB NVMe, AUD 78.40/mo).**

| | monthly |
|---|---|
| cancel Render (Standard 2 GB + ~60 GB disk) | **−US$40** |
| resize syd2 (std-4vcpu → std-6vcpu, +AUD 39.20) | **+US$26** |
| **net** | **≈ −US$14/mo — cheaper than today, with 2× RAM/CPU and 180 GB** |

Fleet cash after: ≈ US$78/mo, and it absorbs the assets, the tenant
Postgres, thalon's offload and Project 1's compute with real headroom.
Supabase Storage keeps the ~38 GB source (~US$0.80/mo) as the durable
origin; **exclude `bio_assets/` from restic** — backing up 40 GB of
reproducible public data nightly is waste, the re-seed IS the restore path
(record that as an explicit, tested exception, not an omission).

**Sequencing (separation of duties):** Swordfish resizes the box, prepares
+ mounts the asset path, sets backup exclusions, and hands off connection
details. **Project 1's agent runs the materialization + app cutover** — we
do not reach into their codebase. Render is cancelled only after their
re-seed verifies sha256-green on the box.

## Founder questions (answered above — kept for the record)

1. The ≥100 GB RLS database — **which project's data is it?** If Project 1
   clinical/compliance: it stays managed (charter invariant) and option D
   applies. If Thalon/other: self-host is on the table.
2. "Supabase equivalent" — do you mean **just Postgres+RLS**, or do you use
   Supabase's **auth / auto-API / realtime / storage** too?
3. The Render disk assets — **HTTP-served static files, or does the app read
   them off the filesystem?** (B2+CDN at ~US$0.36/mo vs box NVMe.)
4. Rough **growth rates** — assets "60 GB and more" and the DB — over the
   next 6–12 months? (Decides 180 GB vs 300–400 GB class.)
5. Budget appetite: comfortable lifting infra cash to **~US$78 (option A)**
   or **~US$104 (option B)** when the workloads land?

## Addendum 2026-07-14 — Render cancel safety (founder Q&A)

Cancelling Render **deletes its persistent disk** (no export path exists), but
the disk is a **derived cache** — the authoritative assets live in Project 1's
private Supabase source-asset bucket. Cancel is therefore a pure cost cut IF
the sequence holds: **resize → re-seed box from Supabase (Project 1's agent,
over 443) → checksum-verify vs source → only then cancel.**

**Mandatory re-seed runbook step (founder-directed 2026-07-14):** before
anyone cancels, Project 1's agent must **confirm nothing exists ONLY on the
Render disk** — e.g. locally-generated derivatives that were never uploaded
back to the source bucket. "The disk is a cache" is the design claim; the
re-seed is the moment to prove it against the live disk (listing/manifest
diff vs bucket), not assume it. Also: the syd2 landing zone joins the restic
set BEFORE assets land (backups-before-workloads, invariant).
