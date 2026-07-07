# Platform-parity research & target architecture — PaaS → VPS

_Researched 2026-07-07 (founder-directed pre-Bucket-3 planning pass). Question answered here:
"the projects live on Vercel / Render / Supabase / AWS today — what must the VPS offer so it is
a genuine landing zone, not a downgrade?" Guarded-token rule applies: migration targets are only
ever Project 1 / 2 / 3. Nothing in this doc executes before Bucket 3 (backups-before-workloads
is invariant); adoption points are pinned to buckets in §9._

## 0. TL;DR

- **Parity is mostly already designed in.** Dokploy + Traefik + CI→GHCR covers the
  Vercel/Render deploy loop (git-push deploy, preview deploys, TLS, custom domains, cron,
  workers, volumes). The real gaps are: **an AI gateway**, **object storage**, **a bigger
  box** (RAM/disk), and **an analytics lane** (DuckDB/Parquet). All four have strong OSS or
  cheap-managed answers below.
- **Founder's spec (>8 GB RAM, >100 GB disk, AU latency)** is satisfiable inside the $30/mo
  ceiling: BinaryLane Sydney 4 vCPU / 8 GB / 100 GB NVMe ≈ **AU$39.20 ex-GST ≈ US$26/mo**.
  Vultr Sydney equivalent is US$40 (breaches ceiling). Decision belongs at the Bucket-5 gate.
- **Supabase stays managed for Project 1** (keep-managed invariant). RLS itself is plain
  Postgres — new/dogfood workloads get RLS on the box Postgres without Supabase.
  Full Supabase self-host is real but wants 4–8 GB RAM by itself → only on a 16 GB box, only
  if a bill or sovereignty forces it.
- **Portability**: after Bucket 3, "switch provider" = create box (script) + converge
  (scripts) + restic restore (drill-tested) + DNS flip. The provider-specific surface is
  three calls (create-box, firewall, DNS A-record) — kept behind a thin adapter seam so
  Vultr → BinaryLane/Hetzner is an afternoon, not a re-build.
- **Terminal**: yes — SSH (CI-as-hands + hotspot break-glass) and Dokploy's built-in web
  terminal over 443. **Pi (pi.dev)**: good candidate harness for the *post-resize* on-box
  agent pilot; not now (2 GB box, 638 M headroom).

## 1. Target spec & provider matrix (live-checked 2026-07-07)

Founder wants: **>8 GB RAM** (Render tier today is 2 GB), **>100 GB disk** (more than the
current Render/Supabase allowances), AU latency for interactive workloads.

| Provider (region) | ~8 GB tier | Disk | Transfer | Price | Notes |
|---|---|---|---|---|---|
| **BinaryLane (SYD NextDC S1)** | 4 vCPU / 8 GB | 100 GB NVMe | 4 TB | **AU$39.20/mo ex GST (≈US$26)** | Hourly billing; resize on demand; 16 GB = AU$78.40 (180 GB NVMe); cheap HDD storage plans (500 GB–8 TB, $20–240) for bulk disk; AU-owned, 4 AU DCs |
| Vultr (SYD) — current provider | 4 vCPU / 8 GB shared | ~160 GB | — | US$40/mo | Simple resize path from syd1 (no migration), but breaches the $30 ceiling |
| OVHcloud (SYD) | VPS tiers A$6.29–A$32.81 ex GST | NVMe | ⚠ APAC quota: 0.5–3 TB then **capped 10 Mbps** | ~A$32.81 for the upper tier | Cheapest AU-region, but the bandwidth cap is a trap for user-facing apps |
| Hetzner (EU; SG exists, dearer) | 4 vCPU / 8 GB (CX33) | 160 GB* | 20 TB | ~US$8–15/mo EU | 3–5× cheaper compute, no AU region — stays the **Bucket-7 egress-box** candidate (charter already notes this) |
| Contabo (SYD at premium) | 6 vCPU / 16 GB | large | — | ~US$11 EU-price | RAM/$ king; support/reputation caveats; keep as documented budget fallback only |

\* getdeploying.com aggregate; exact disk varies by line. All prices re-verified at the spend
gate — treat this table as ranking, not quotes.

**Read on the matrix:** BinaryLane is the standout for the founder's spec — AU latency,
inside the ceiling, and disk growth via cheap HDD volumes. Hetzner remains wrong for
interactive AU workloads but right for latency-tolerant egress (Project 3 offload).
Two paths at Bucket 5, founder's call:

- **(a) Resize in place** on Vultr to 8 GB (US$40 — needs a ceiling amendment), zero
  migration risk; or
- **(b) Graduate-by-migrating** to BinaryLane 8 GB — lands the spec *inside* the ceiling
  **and doubles as the portability drill** (§6): provision box #2 from scripts, restore from
  B2, flip DNS. Proves the crown-jewel claim on real hardware.

Sources: binarylane.com.au/vps-hosting/linux-vps · ovhcloud.com/en-au/vps ·
getdeploying.com/reference/compute-prices · vultr.com/pricing.

## 2. Parity map — what each PaaS actually provides vs the VPS answer

### 2.1 Vercel (Next.js hosting for the frontend projects)

| Vercel feature | VPS answer | Status |
|---|---|---|
| git-push deploy + build | Dokploy (Railpack/Nixpacks or Dockerfile) or our CI→GHCR→deploy lane (image bar enforced) | ✅ have |
| Preview deployments per PR | Dokploy preview deployments (per-app toggle, own subdomains) | ✅ have, unused yet |
| TLS / custom domains / HTTP2 | Traefik TLS-ALPN, HSTS, headers | ✅ live |
| ISR / Data Cache / image optimization | Work self-hosted via `next start` / `output: "standalone"`; `sharp` must be installed in the runner image; cache lives in `.next/cache` — fine single-instance, needs a volume to survive redeploys | ✅ works, document in the app-handoff pack |
| Edge network / CDN | None on-box. Cloudflare free tier in front = documented upgrade (charter decision 3 already notes orange-cloud → DNS-01 switch) | 📋 upgrade path |
| Serverless/edge functions, cold starts | Not needed — a long-running Node server is strictly *more* capable (persistent WebSockets, no cold starts, no 10 s/300 s limits) | ✅ n/a — VPS wins |
| Vercel KV / Blob / Postgres / Queues | Redis container / R2-B2 object storage (§2.4) / box Postgres (§2.3) / BullMQ on Redis | ✅ standard containers |
| Analytics / Speed Insights | Optional: Umami or Plausible container (both self-host staples) | 📋 optional |
| **AI Gateway** | §3 — the one genuinely new service to stand up | ⚠ gap → plan |

Key fact for the handoff pack: Next.js self-hosting is first-class in 2026 — standalone
output + sharp + a persistent `.next/cache` volume gives full ISR/image parity on one box
(multi-instance would need a Redis cache-handler; irrelevant at our scale).
Sources: nextjs.org/docs/app/guides/self-hosting.

### 2.2 Render (the RAM/disk/worker tier the founder is outgrowing)

Render's value = persistent disk, background workers, cron, private services. All are native
VPS strengths: Dokploy volumes (+ restic, with pre-backup dump hooks — Bucket 3), plain
worker containers on internal networks, Dokploy schedules for cron, vertical resize instead
of autoscaling. **Nothing to build; parity is the default.** The only Render feature without
an equivalent is managed-Postgres PITR — restic snapshots + nightly dumps are the v1 answer;
PITR (pgBackRest/WAL-G) is a documented upgrade if a workload ever earns it.

### 2.3 Supabase (RLS Postgres)

- **Invariant unchanged:** Project 1's compliance-bound data plane stays on managed
  Supabase. Never migrated.
- **RLS is a Postgres feature, not a Supabase feature.** New/dogfood workloads get
  Postgres 17 (Dokploy-managed container) with RLS policies + scoped roles directly. If an
  app wants the supabase-js client-side query pattern, add **PostgREST** (the same engine
  Supabase uses) as one container; auth for new apps via **Better Auth** (MIT, TS) or
  app-side sessions.
- **Full self-host Supabase** (official docker compose) is viable but heavy: 1.5–4 GB idle,
  4 GB min / 8 GB recommended, and self-host lacks platform features (multi-project Studio,
  managed backups/PITR, branching, advanced observability). Consensus trigger: self-host
  when the cloud bill clears ~$200/mo or sovereignty demands it. **Decision: à la carte
  (Postgres+RLS ± PostgREST) on the 8 GB box; full Supabase only ever on a 16 GB box, as its
  own bucket, behind a gate.**
- Sources: supabase.com/docs/guides/self-hosting/docker · supascale.app self-host guides ·
  github.com/orgs/supabase/discussions/26159.

### 2.4 AWS (the glue)

| AWS piece | VPS-era answer |
|---|---|
| S3 | **Cloudflare R2** (zero egress — already the charter's Bucket-7 artifact-store pick) or B2 (backups stay here). Self-host only if sovereignty forces it: **SeaweedFS** (Apache-2.0, the safe pick) or **Garage** (AGPL → service-use only, licensing ledger like Renovate). **MinIO is out** — community edition in maintenance mode since late 2025, admin UI gutted. |
| SQS / background jobs | Redis + BullMQ containers |
| Lambda / cron | containers + Dokploy schedules |
| CloudFront | Cloudflare free tier (documented upgrade) |
| SES / email | stays managed (Resend or similar) — never self-host deliverability |
| IAM / secrets | scoped API keys now; **Infisical at box #2** (charter decision 7, unchanged) |

Sources: dev.to + lowcloud.io + akmatori.com MinIO-alternatives roundups (2026).

## 3. AI gateway (the Vercel AI Gateway replacement)

What Vercel AI Gateway gives the projects today: one OpenAI-compatible endpoint + AI SDK
provider for 40+ providers (incl. **Groq/Llama-3.3 and Gemini** — the ones in use), automatic
failover, BYOK at zero markup, spend monitoring. Two important facts:

1. **It is not coupled to Vercel hosting.** It's a hosted endpoint + key; an app on our VPS
   can keep calling it unchanged. So this is a *decoupled* migration decision — apps can move
   first, gateway later.
2. Apps built on the AI SDK / OpenAI-compatible interface swap gateways with **one base-URL
   env var**. That's the portability seam to preserve in the handoff pack.

Self-host candidates (all deployable as one Dokploy service at `ai.swordfish.cfd`):

| | License | Runtime | Overhead | Notes |
|---|---|---|---|---|
| **Bifrost** (Maxim) | Apache-2.0 | single Go binary | ~11 µs, tiny RAM | governance, semantic caching, adaptive LB; clean supply chain (one binary) — **recommended primary** |
| LiteLLM | MIT core | Python | 10–50 ms, ~0.5 GB+ | most battle-tested, 100+ providers, virtual keys/budgets/UI; ⚠ two backdoored PyPI releases (1.82.7/.8, 2026-03) — pin + verify if chosen |
| Portkey Gateway | Apache-2.0 (fully OSS since 2026-03) | Node | small | guardrails/PII redaction focus — the compliance-heavy alternative |

**Plan:** stand up **Bifrost** as a dogfood service (Bucket 4/5 era, after backups), BYOK
Groq + Gemini keys as compose secret-files (→ Infisical at box #2), per-project virtual
keys + spend caps, JSON usage logs. Vercel AI Gateway stays the documented fallback (works
from anywhere, zero markup). Projects connect themselves per separation-of-duties — Swordfish
hands them a base URL + key.

Also: the same gateway endpoint serves **on-box agents** (§7) — one choke point for all LLM
spend, human and agent, with budgets enforced server-side.

Sources: vercel.com/docs/ai-gateway · techsy.io/en/blog/best-llm-gateway-tools ·
truefoundry.com/blog/bifrost-vs-litellm · medium LiteLLM-supply-chain post-mortems (2026-03).

## 4. Analytics lane — DuckDB + Parquet (founder's instinct is right)

The 2026 state of the art matches the idea exactly:

- **pg_duckdb 1.0** (MIT, DuckDB Labs — production-ready since its 1.0) embeds DuckDB's
  vectorized engine **inside Postgres**: query/write Parquet, CSV, Iceberg, Delta on
  S3-compatible stores (R2/B2) as if they were tables, from the same connection string the
  app already has. Ships as a prebuilt Docker image (`pgduckdb/pgduckdb`) — on Dokploy this
  is just "use a custom Postgres image".
- **DuckLake / pg_ducklake 1.0** adds lakehouse semantics (ACID, time travel, partitioning)
  over Parquet-in-object-storage with the catalog *in Postgres* — no Iceberg/Spark machinery.
  Verify its license at adoption time.
- **Pattern for us:** hot/transactional rows in Postgres (RLS intact) · workers write
  event/artifact data as **Parquet to R2** (zero egress) · pg_duckdb queries both in one SQL
  statement. This is precisely shaped for **Project 3's offload workload** (render workers →
  Parquet artifacts → cheap analytical reads) and costs nothing until then.
- **Adoption point:** Bucket 7 (Project 3 box) for real; optional earlier dogfood = analyze
  our own Traefik JSON access logs into Parquet as the pilot.

Sources: github.com/duckdb/pg_duckdb · motherduck.com/blog/pg-duckdb-release ·
pgducklake.select/blog/introducing.

## 5. Edge-architecture notes (founder-supplied Atlassian deep-dive, local/untracked)

The founder provided a write-up of Atlassian's Envoy-based edge (xDS dynamic config, auth
sidecars at the proxy, global rate limiting, SQS-driven self-service broker, IaC-templated
regions, canary rollouts). Verdict: **the patterns validate our design at 1/1000th the
scale; adopt four, reject the hyperscale machinery.**

Adopt (each maps to an existing seam):

1. **Auth at the edge, not per-app** (their auth sidecars) → Traefik **forward-auth**
   middleware in front of every admin UI (Dokploy, Kuma, Beszel, Bifrost UI) — one login
   choke point, blast-radius reduction. Candidates: TinyAuth (light) or Authelia (SSO/2FA).
   Opinion ratchet; lands Bucket 4/5. (Each UI keeps its own auth too — defense in depth.)
2. **Overload protection at the edge** → Traefik `rateLimit` + `inFlightReq` middleware on
   public routers, tracked config next to the existing security-headers middleware. Cheap,
   config-tier; CrowdSec at box #2 remains the escalation (already chartered).
3. **Self-service broker** (their FastAPI+SQS+DynamoDB) → validates our **Dokploy API/MCP +
   CI as the broker**: agent proposes, API executes, state lives in inventory/ + Dokploy —
   the North-Star `swordfish provision <box>` is this pattern at shell scale. No new build.
4. **Canary/staged rollout** → Dokploy preview deployments + a staging environment on the
   same box; validate before promoting. Free to adopt per-app.

Reject at our scale: Envoy itself (Traefik's docker/file providers already give us the
dynamic-config property xDS provides), anycast/multi-region, DynamoDB state stores,
horizontal autoscaling. Revisit only if a workload ever outgrows one box per region.

## 6. Portability — "the next provision must be fast"

The knowledge already lives in executable form (that's rule 9); what makes provider-switch
fast is knowing **which 5% is provider-specific** and keeping it behind a seam:

- **Provider-specific (the adapter):** create-box (API call w/ plan+region+cloud-init),
  provider firewall (22/80/443), DNS A-record. Today: `provisioning/vultr/create-box.ps1`,
  Vultr firewall script, `provisioning/dns/set-a-record.ps1` (Porkbun — already
  provider-neutral). A BinaryLane or Hetzner adapter is one script each against their APIs;
  same inputs, same output (an IP).
- **Provider-agnostic (everything else):** cloud-init, phase scripts, compose/edge, Dokploy
  install, resticprofile, CI smoke — none of it knows or cares which company rents the box.
- **Migration = provision + restore + flip:** create box #2 from scripts → converge →
  `restic restore` from B2 (drill-tested every month from Bucket 3) → lower-TTL DNS flip →
  decommission. The restore drill **is** the migration rehearsal; RTO measured in
  `runbooks/` becomes the honest "how fast can we switch" number.
- **Formalization ladder unchanged:** Ansible + dev-sec at box #2, OpenTofu at box #3+
  (state-encrypted, has Vultr *and* Hetzner providers; BinaryLane via API script until/unless
  a provider exists). Action now: **none** — just structure `provisioning/` so the adapter
  boundary is visible (a `provisioning/<provider>/` dir per provider, everything else
  provider-neutral). That's a file-move, done opportunistically in Bucket 3+.

## 7. Terminal on the box & on-box coding agents (Pi)

**Yes, there's a terminal — three of them:**

1. **SSH** — the real one. Office blocks 22 → CI-as-hands executes; phone hotspot =
   break-glass raw SSH (standing posture, unchanged).
2. **Dokploy web terminal** — built into the UI over 443: server shell + per-container
   shells. Works from the phone; office FortiGate MITM caveat applies (never over corp
   proxy).
3. **CI** — the scripted hands; anything repeatable belongs here, not in an interactive
   shell.

**Pi (pi.dev)** — assessed: minimal open-source agent harness (MIT), TUI + RPC + SDK,
15+ providers incl. Groq and Gemini, AGENTS.md-aware, extensions-over-features philosophy.
It's a *good* candidate for the already-chartered **on-box agent pilot** (Checkpoint-1
amendment 6 — cron briefings, alert triage, runbook one-liners), because: tiny footprint,
MIT, provider-agnostic (would talk to our own Bifrost gateway → budgets enforced at the
gateway, spend visible in one place), and AGENTS.md is the contract format this repo already
speaks. **Not now:** the 2 GB box has 638 M headroom and the pilot is pinned post-Bucket-5
resize with its own LLM-budget gate. Posture unchanged: an on-box agent never holds
spend-capable provider keys, socket access, or provisioning authority; it gets E0-eyes →
E1-propose graduation, gateway-issued LLM key with a hard cap. Claude Code (headless over
SSH) is the alternative harness; pick at the pilot's go/no-go.

## 8. Target architecture (the parity stack on an 8 GB box)

```
                     Cloudflare (documented upgrade, not v1)
                              │
                    Traefik v3 + socket-proxy          ← edge: TLS, HSTS, rate-limit,
                              │                           forward-auth (admin UIs)
   ┌───────────┬──────────────┼────────────────┬──────────────────┐
 Dokploy    apps (Next.js   Postgres 17       Bifrost          monitoring
 (control    standalone,    (pgduckdb image:   AI gateway      (Kuma + Beszel
  plane +    workers,       RLS + pg_duckdb    ai.swordfish…    + ntfy)
  previews,  BullMQ+Redis)  → Parquet on R2)   BYOK Groq/Gemini)
  schedules)
   └────────────── restic → B2 (nightly, drilled monthly) ──────────────┘
              objects/artifacts → Cloudflare R2 (zero egress)
```

RAM budget @ 8 GB: OS+Docker ~0.5 · edge ~0.15 · Dokploy ~0.7 · Postgres ~1.0 · Redis ~0.1 ·
two Next.js apps ~0.8 · Bifrost ~0.1 · monitoring ~0.2 → **~3.5 GB used, ~4.5 GB headroom**
(vs today: 2 GB total, 0.6 GB free). Full self-host Supabase would eat the headroom whole —
hence the 16 GB gate in §2.3.

## 9. Charter impact (nothing re-opens; adoption points only)

| Bucket | This doc adds |
|---|---|
| **3 (next, unchanged)** | Backups exactly as chartered. Opportunistic: make the `provisioning/<provider>/` adapter boundary visible while touching files. |
| 4 | Optional config-tier: Traefik rate-limit middleware; forward-auth candidate noted. |
| **5 (gate)** | The §1 decision: resize-in-place (US$40, ceiling amendment) **vs graduate-by-migrating to BinaryLane 8 GB (≈US$26, doubles as portability drill)**. Bifrost gateway lands as a dogfood service. Handoff pack gains: Next.js self-host notes (standalone+sharp+cache volume), gateway base-URL seam, Postgres+RLS connection pattern. |
| 6 | Unchanged (Ansible, Infisical, CrowdSec). PostgREST/Better Auth offered in the handoff pack if Project 1's app tier wants them. |
| 7 | R2 artifact store + **pg_duckdb/Parquet lane** for Project 3 offload (verify pg_ducklake license at adoption). |
| post-5 pilot | Pi vs Claude-Code-headless as the on-box agent harness; LLM key issued by our own gateway with a hard budget. |

## 10. Open questions for the founder

1. **Bucket-5 path:** resize-in-place (Vultr, US$40, needs ceiling bump) or
   graduate-by-migrating (BinaryLane, ≈US$26, proves portability)? No decision needed until
   the Bucket-4 checkpoint; flagged now so it can simmer.
2. **AI gateway posture:** OK to keep projects on Vercel AI Gateway until our Bifrost is
   drilled (it's host-independent, zero markup), then swap by env var? (Recommended: yes.)
3. **Supabase:** confirm à-la-carte stance (Postgres+RLS on-box for new workloads; managed
   Supabase untouched for Project 1; full self-host only ever as its own gated bucket on
   16 GB). Which project drives the >100 GB disk want — reference data (Bucket 6 block
   storage) or artifacts (R2/HDD-volume, cheaper)?
4. **Forward-auth SSO** in front of admin UIs at Bucket 4/5 — worth the extra moving part,
   or keep per-app auth + 2FA only? (Recommended: yes at box #2 / fleet, optional before.)
