# Eamos asset migration — Render → syd2, readiness-first plan (2026-07-15)

> **2026-07-15 (later):** Project 1 **unmasked as Eamos** by founder call —
> the name may appear in tracked files; provisioned `project1` slugs stay.
> Phase 0 is COMPLETE (landing zone · verified restic exception · deploy-only
> tenant pack · harness); Phase 1 handed to Eamos's agent via
> `~/work/eamos/agent_handoff/FROM-SWORDFISH.md`.
>
> **2026-07-16:** Phase 1 **COMPLETE + double-verified** by both sides. ClinGen
> `527,925,248 B` pulled Supabase→syd2, md5+sha256 green; the
> nothing-lives-only-on-Render proof is green (`render_only=0`), retired early.

---

## ⚠️ 2026-07-17 AMENDMENT — the resize is NOT on the critical path to cancelling Render

_Founder ask: "organise the full migration so I can cancel Render." Re-measured
syd2 live rather than trusting this doc's own July-15 estimates — and the
sequencing premise below (§Phase 2 before §Phase 3) **no longer holds.**_

**What this plan assumed:** the ~41 GB corpus would squeeze a 100 GB disk, so
the resize must precede the bulk seed.

**What syd2 actually shows (measured 2026-07-17, `df` + `docker stats`):**

| | measured | after a 41 GB seed | verdict |
|---|---|---|---|
| disk | 99 G total, **81 G free** (15 G used) | ~40 G free | seed fits, with room |
| RAM | 7,941 MB total, **6,037 MB available** (~1.4 G actually in use) | −~2 G for the Eamos backend → ~4 G spare | app cutover fits |

The RAM headline is the one that matters and it is easy to misread from config
alone: **thalon-web is consuming 92 MiB against a 4 GiB cap.** That cap is a
*limit, not a reservation* — it was read as "4 GB is spoken for", and it is not.
The largest real consumer on the box is Dokploy itself at 1,023 MiB.

**Therefore the resize gates _Thalon's render worker_, not Eamos's migration.**
Those two needs were bundled into one gate (they genuinely share one resize),
and the bundle has been quietly holding Render hostage to a spend that
Eamos does not need.

**Consequence for the founder's actual goal — the money moves the other way:**

- **As sequenced here:** pay **+AUD 39.20/mo** (resize) → *then* seed → cutover
  → soak → cancel Render (−US$40/mo). Spend precedes saving.
- **Decoupled:** seed → cutover → soak → **cancel Render (−US$40/mo now)** →
  resize later, on Thalon's timeline, when its worker actually needs the RAM.
  Saving precedes spend, and the resize is then judged on Thalon's merits with
  the assets already proven on the box.

Nothing about the *safety* preconditions changes — Phase 4's three gates below
stand exactly as written. This amendment reorders spend, not proof.

**Revised sequence (supersedes the Phase 2 → Phase 3 ordering below):**

1. **Phase 3a — bulk seed at current size.** Zero spend. Eamos drives. The long
   pole (~41 GB + checksums), and it needs nothing from the founder's wallet.
2. **Phase 3b — Eamos backend cutover to syd2.** ~2 GB into ~6 GB available —
   strictly *more* headroom than Render Standard's 2 GB gives it today, which
   also de-risks Eamos's known `protein_annotation` OOM history.
3. **Phase 3c — parallel-run soak** (≥48 h suggested; Eamos's call), Render live.
4. **Phase 4 — ⛔ founder cancels Render.** Preconditions unchanged.
5. **Phase 2 (was first, now last) — resize, if and when Thalon's worker needs
   it.** Re-priced live at the gate, never from memory.

**The one open risk this amendment carries, for Eamos to close before the seed:**
peak *transient* disk during materialization. 81 G free covers the 41 G result,
but not a hypothetical 2× staging pass (41 G download + 41 G extract = 82 G >
81 G). The ClinGen dry run streamed a single 528 MB object cleanly, which
suggests per-object streaming (peak ≈ final + one object) — **suggests, not
proves.** Eamos confirms the materialization run's peak disk behaviour before
the bulk run; if it stages 2×, the resize returns to the critical path and the
spend gate genuinely fires first.

---

_Founder directive 2026-07-15: prove the VPS is ready BEFORE the resize spend,
then wake Project 1's agent on the box and run the migration as a coordinated
job. This doc is that plan. It reorders (does not change) the economics and
safety work in `capacity-and-data-plan-2026-07-13.md` — read that for the
numbers; read this for the sequence. Nothing here authorizes spend: the resize
and the Render cancel each remain explicit founder gates._

## What moves, what never moves (standing invariants)

| | where it lives after |
|---|---|
| ~41 GB reference-asset tree (dbSNP, phyloP, ClinVar, RepeatMasker, ClinGen) | **syd2 NVMe** (bind-mount path) |
| Project 1 app compute (Render Standard, ~US$25/mo) | **syd2 container** (their CI → GHCR → Dokploy, digest-pinned) |
| Supabase Postgres + auth (clinical/compliance data plane) | **stays managed — keep-managed invariant, never migrates** |
| Supabase Storage source-asset bucket (~38 GB) | **stays managed — it IS the source of truth; the box disk is a cache of it** |

Load-bearing fact (verified 2026-07-13): the Render disk was *seeded* from the
Supabase bucket via their own materialization endpoint (7/7 ready, all sha256
verified). Re-seeding the box uses the same proven run. There is no rescue
deadline and nothing to "copy off" Render.

## Phase 0 — pre-stage the landing zone (swordfish, ZERO spend, can start now)

1. **Landing zone**: create the asset path on syd2 (proposal: `/srv/project1/assets`,
   owner/mode agreed with their agent at wake-up), plus a `manifests/` dir for
   seed manifests + checksums.
2. **Backup posture BEFORE data** (invariant): manifests/config join the restic
   set; the bulk corpus itself is an **explicit, recorded exclusion** — it is
   reproducible public reference data and the re-seed IS its restore path
   (`capacity-and-data-plan-2026-07-13.md` sizing section). Run one restic
   backup+restore drill proving the exclusion behaves (manifests restored,
   corpus excluded, nothing else newly excluded).
3. **Tenant pack**: Dokploy project + scoped tenant credential for Project 1
   (same `tenant-credential.sh` pattern as Thalon). NOTE: the key-scope gate
   (security review finding 2, deploy-without-create) should be resolved first
   so their key is born properly scoped instead of rotated later.
4. **Verification harness**: a small box-side script their agent can call —
   walks the asset tree, emits `sha256 + size + relpath` manifest, diffs
   against a supplied source manifest. Deterministic, no LLM in the loop.
5. **Disk math, written down**: syd2 today = 100 GB, ~85 GB free. The corpus
   *fits today* but leaves ~44 GB for Postgres + Docker churn + Thalon + asset
   growth (hg38.2bit / Protein View queued). That squeeze is WHY the resize
   precedes the bulk seed — but nothing in Phase 0 needs it.

**Exit criteria (= "the VPS is ready", what the founder asked to see):**
landing zone exists · restic drill green with the recorded exception ·
tenant pack issued · verification harness runs against a fixture tree.

## Phase 1 — wake Project 1's agent on the box (founder + swordfish)

- Founder starts Project 1's session on this box (cryosleep wake-up: repo
  clone/pull under `~/work/`, creds via their own channel, 5-point wake-up
  checklist per the captain-of-the-ship protocol; a relay topic if he wants
  Telegram reach). Swordfish pre-stages everything pre-stageable; his part
  stays paste/tap/click.
- Joint dry-run at current size (zero spend): their agent pulls **one small
  asset** (e.g. clingen, ~528 MB) from the Supabase bucket over 443 into the
  landing zone, verification harness confirms sha256 — proves the whole
  pipe end-to-end (auth, egress, path, harness) for cents of bandwidth.
- Their agent produces the **source-bucket manifest** and the **live Render
  disk manifest**, and diffs them: this is the mandatory
  **nothing-lives-ONLY-on-Render proof** (founder-directed 2026-07-14),
  done EARLY while Render is still alive and mistakes are free.

**Exit criteria:** dry-run asset verified on box · manifest diff reviewed —
anything Render-only is uploaded back to the source bucket before we proceed.

## Phase 2 — ⛔ SPEND GATE: resize syd2 → std-6vcpu (founder says "resize go")

- AUD 78.40/mo (+39.20); net ≈ **US$14/mo cheaper** once Render cancels.
  In-place BinaryLane resize, grow-only disk, brief reboot, no data at risk.
- Swordfish executes: resize → boot checks → smoke suite green → restic
  backup post-resize → confirm 180 GB visible.
- Also unlocked by this gate: Thalon's render worker at its full 3–4 GB cap
  (currently queue-of-one fallback) — one resize serves both tenants.

## Phase 3 — coordinated re-seed + cutover (Project 1's agent drives)

1. Their agent runs the **same materialization run that seeded Render**,
   targeting the box path, over 443. Expect ~41 GB from the Supabase bucket.
2. Verification harness: sha256 manifest vs source — **must be 7/7 green**,
   recorded into `manifests/` (restic-covered).
3. App cutover on their side (env/asset-path flip, their `render.yaml`
   equivalent moves to the Dokploy service) — swordfish hands off connection
   details only, never reaches into their codebase.
4. Parallel-run: Render stays up while the box serves; their agent decides
   the soak length (suggest ≥48 h, matching our cutover pattern).

## Phase 4 — ⛔ CANCEL GATE: Render cancel (founder, LAST and only after)

Preconditions, all three, no exceptions: ① re-seed checksum-green on box ·
② nothing-only-on-Render proof done (Phase 1) and any stragglers uploaded ·
③ parallel-run soak clean. Cancelling deletes the Render disk irreversibly —
which is fine, because by here it is a proven cache. Savings land: −US$40/mo.

## Roles (separation of duties, binding)

- **Founder**: wake Project 1 · "resize go" (Phase 2) · cancel Render (Phase 4).
  Everything else is pre-staged so his steps stay one-liners.
- **Swordfish**: Phases 0 + 2, harness + backup posture, connection handoff,
  coordination notes (FROM-SWORDFISH / ASK-BACKS pattern, as with Thalon).
- **Project 1's agent**: manifests + proof (Phase 1), re-seed + app cutover
  (Phase 3). Their codebase stays theirs.

## Risks & mitigations

- **Disk squeeze if seeded before resize** → sequence forbids bulk seed pre-resize;
  dry-run asset is deliberately the smallest.
- **Render-only derivatives lost at cancel** → Phase 1 manifest diff while
  Render is alive; cancel gate hard-requires it.
- **Bandwidth**: ~41 GB ingress to BinaryLane (ingress free; Supabase egress
  on their plan — their agent confirms quota before the bulk run).
- **Growth outruns 180 GB** → revisit at re-charter with real growth rates
  (capacity plan question 4 stays open).
