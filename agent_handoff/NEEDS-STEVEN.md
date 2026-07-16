# NEEDS STEVEN — the founder action queue

> Agent-maintained. One line per OPEN founder action:
> `- [YYYY-MM-DD] text` (date = when it was raised; the dashboard shows age).
> Remove a line ONLY when its source says done — the dashboard renders this
> file verbatim and never invents or retires state on its own.
> ⛔ Guarded project names never go here (tracked file — Project 1/2 only).

- [2026-07-13] ⛔ **SPEND GATE — resize syd2** = **Phase 2 of `research/project1-asset-migration-plan-2026-07-15.md`**. **Phase 1 is COMPLETE + double-verified 2026-07-16** (ClinGen 527,925,248 B pulled Supabase→syd2, md5+sha256 green; nothing-lives-only-on-Render proven `render_only=0`) — so this is now **purely your call, nothing is waiting on any agent**. Live-priced 2026-07-16 (BinaryLane API, not memory): `std-6vcpu` = 6 vCPU / **16 GB** / 180 GB / 5 TB = **AUD 78.40/mo (+39.20)** — the cheapest 16 GB tier they sell in syd. **You HELD it 2026-07-16** after being shown two non-obvious costs: a resize needs a **power-off** (Dokploy + thalon's app + tenant-pg all briefly down → needs a peer-coordinated window) and the disk grows 100→180 GB which **cannot be shrunk back** (one-way). Nothing is blocked today (syd2: 79 GiB free of 100); the real trigger is **Phase 3's ~41 GB bulk seed**. Still also gates thalon's render worker at full size. **Render is cancelled LAST and only at the plan's Phase-4 gate** (checksums green + nothing-only-on-Render proven + soak clean).
- [2026-07-16] **POSTURE RULING wanted (no rush, nothing broken): syd4 can now SSH straight into syd2.** Disabling BinaryLane's outbound port-blocking on syd4 (your approval, for Render access) revealed that syd4's key was *always* authorized on syd2 — the "CI-as-hands only" property was accidentally enforced by the provider filter, not by policy. Nothing on syd2 was weakened; syd4 merely gained egress. Effect: agents on the workspace box can now administer production directly, bypassing the CI channel your charter chose. It is convenient (today's read-only probes used it) but it is a real reach expansion. **Keep** (say nothing) **or close** (drop that key from syd2's `authorized_keys`; probes move back to CI — costs a few minutes per check, no capability lost).
- [2026-07-13] subscriptions.yml FILL fields — 3 remain in `inventory/secrets/subscriptions.yml` (edit the file or tell any agent): Claude → which card; GitHub → next_charge date + which card (from the receipt).
- [2026-07-13] Gmail MCP re-auth (token EXPIRED) — one click in claude.ai settings; unblocks receipt-driven subscriptions.yml fills.

_Accounted 2026-07-15 (informational lines, read + acted): Dokploy bookmark
(deploy.swordfish.cfd, in use since cutover) · thalon staging one-login note
(creds in `~/COPY-ME.txt`). Render-cancel guardrail folded into the spend-gate
line above — it is Phase 4 of the migration plan, not a separate action._

_Ruled 2026-07-16 (raised + decided same session, no longer needs him):
**render-only content** — Project 1's agent proved 10 objects (5.06 GB) live
only on the Render disk with no identity match in the source bucket (the
nothing-lives-only-on-Render check firing exactly as designed, early, while
Render is alive). Founder ruled **exact-byte preservation**: upload that set
(and only that set) to the bucket, rerun the comparator to `render_only=0`,
then the ClinGen dry run proceeds. No spend (~5 GB against 57 GB free
storage). Phase-4 blocker retired rather than carried; the alternative —
editing a passing safety test to accept the gap — was declined. Egress
readout that unblocked the gate: Pro, 25 Jun–25 Jul cycle, 0.014 of 250 GB
used._
