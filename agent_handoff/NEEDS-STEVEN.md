# NEEDS STEVEN — the founder action queue

> Agent-maintained. One line per OPEN founder action:
> `- [YYYY-MM-DD] text` (date = when it was raised; the dashboard shows age).
> Remove a line ONLY when its source says done — the dashboard renders this
> file verbatim and never invents or retires state on its own.
> (Naming: the portfolio is fully unmasked as of 2026-07-17 — Eamos · Selom ·
> Thalon may all be named here. No guarded tokens remain.)

- [2026-07-17] ⛔ **GATE — release Eamos Phase 3 (the thing that lets you cancel Render).** Say **"Phase 3 go"** and **open the Eamos session**; those two together are the whole ask. Eamos's own written gate holds Phase 3 pending *a new explicit founder gate* — no agent may reinterpret that, so it waits on your word, not on work. **Phase 3 is theirs to drive** (separation of duties: swordfish never touches their codebase), which is why the session must be open. Sequence once released: 3a bulk seed (~41 GB, zero spend) → 3b backend cutover → 3c parallel-run soak (Render live) → **Phase 4: you cancel Render, −US$40/mo**. Pre-brief is already staged in their channel so they boot straight into it. One open question sits with them first: the materialization run's **peak transient disk** (81 G free covers the 41 G result, but not a 2× staging pass) — if it stages 2×, the resize returns to the critical path.
- [2026-07-13→17] ⛔ **SPEND GATE — resize syd2. ⚠️ NO LONGER BLOCKS RENDER CANCELLATION — it is now Thalon's gate, not Eamos's.** Swordfish re-measured syd2 live 2026-07-17 rather than trusting the July-15 plan: **disk 81 G free** (a 41 G seed leaves ~40 G) and **RAM 6,037 MB available** with only ~1.4 G actually in use — `thalon-web` sits at **92 MiB against a 4 GiB cap** (a *limit*, not a reservation; that misreading is what bundled these). So **Eamos's migration fits at the current size**, and its backend gets *more* headroom on syd2 (~6 G avail) than Render Standard's 2 G gives it today. **This flips the money order**: instead of +AUD 39.20/mo *before* saving, you can cancel Render (−US$40/mo) *first* and resize later, on Thalon's timeline, judged on its render-spike profile alone. Live-priced 2026-07-16 (BinaryLane API, never memory): `std-6vcpu` = 6 vCPU / 16 GB / 180 GB / 5 TB = **AUD 78.40/mo (+39.20)**. Unchanged catches when you do take it: needs a **power-off** (Dokploy + thalon + tenant-pg briefly down → peer-coordinated window) and the disk grows 100→180 G **one-way, cannot shrink**. Re-price at the gate.
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
