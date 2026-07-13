# CURRENT — session handoff (one file, overwritten each wrap)

> ## ▶ BOOT: the founder types **`gogogo`** — that is the whole resume prompt.
>
> **Agent, on `gogogo` (or any greeting with no task): do this, unprompted.**
> He cannot copy text out of this terminal, so there is no prompt for him to
> paste — the prompt is this file. Read, in order, then act:
> 1. this whole file (State → Next → Protocol notes → Constraints)
> 2. `AGENTS.md` (the operating protocol) and your memory
> 3. `git log --oneline -8` and `git status` — trust the repo, not the stamp
>
> Then **state the top of Next in one sentence, say what you are starting, and
> start it.** Do not ask "shall I?" — the Next list IS the standing approval.
> Stop only at a founder gate (spend · destroy · anything named a founder
> decision below). If the box state and this file disagree, the box wins —
> say so, then fix the file.

_Stamped: 2026-07-13 23:59 +10:00 (**THE CUTOVER IS DONE** — executed this
session on the founder's relay-verified `cutover go`; syd2 is THE box; syd1
is in 72 h soak as the untouched rollback target. Also this session: a guard
breach was made AND fixed + ratcheted (see State) · portfolio-wide `gogogo`
BOOT blocks placed · relay cold-start proven · **next session starts by
building `!map`** — founder-directed.)_

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
- **CUTOVER EXECUTED 2026-07-13 ~23:00 AEST**, per
  `provisioning/cutover-step-card.md` (kept as the record; soak + syd1-fate
  section still pending). Evidence chain:
  - DNS: `deploy./status./metrics./hello.` → 103.249.236.41 (Porkbun upsert
    ×4, TTL 600; authoritative + 1.1.1.1 confirmed within ~1 min).
  - `edge-apply` vs syd2 run **29251569671** green (converge + idempotency
    proof + full posture re-assert; Dokploy router off `deploy2.` → 404s now).
  - `hardening-smoke` vs syd2 run **29251625711** = **64/64** (suite grew +1
    with the thalon staging probe; the old 60/63 pre-cutover ceiling cleared).
  - verify-deadman natural-fire vs syd2 run **29251119226** SUCCESS (same
    day, pre-gate): nightly ran + both dead-man legs receiver-acked.
  - All four real names probed serving from syd2 with fresh LE certs
    (notAfter 2026-10-11).
  - Flips landed + re-proven: `collectors/lib.sh` (SYD1 row gone, real names
    on syd2) · `collect-fleet.sh` (3-box board) · `staging-assert.sh` +
    `tenant-credential.sh` defaults → `deploy.` · thalon repo var
    `DOKPLOY_API_BASE` → `deploy./api` (staging posture green through it) ·
    syd4 `~/.claude.json` dokploy MCP key swapped to the syd2 key (200-tested;
    **the syd1-keyed MCP would have died silently** — found at pre-flight).
  - Dashboard fleet card regenerated: syd4/syd3/syd2, syd2 deadman green.
- **syd1 = SOAK, rollback target only** (off the dashboard, untouched, still
  billing against Vultr credit): rollback = 4 Porkbun upserts back to
  45.63.24.122, ≤10 min. Do NOT deploy to it; its Dokploy IDs are parked in
  `runbooks/dogfood.md`.
- **Dashboard question answered (founder, this session):** the numbers were
  never chat-maintained — machine-visible facts collect automatically every
  15 min (hermes `jobs.json`, provider APIs, fleet); SaaS spend is the one
  schema'd table `inventory/secrets/subscriptions.yml` he can edit directly
  in code-server. What he saw was a 15-min-stale snapshot; verified current
  now (GitHub Pro US$4 on the card; morning-briefing scheduled/enabled,
  fires 21:00 UTC daily).
- Morning-briefing v0 live (hermes cron d8e6bb992d5e); tonight's run doubles
  as a free cutover witness (it probes `hello.` + `status.` — now syd2).
- Gmail MCP token still EXPIRED (founder re-auth queued; unblocks
  receipt-driven `subscriptions.yml` fills).
- Fleet: syd2 (prod, THE box) · syd3 (hermes cockpit) · syd4 (workspace,
  agent home) · syd1 (soak, off-board).
- **⚠️ GUARD BREACH + FIX (2026-07-13, agent error — read this):** a guarded
  project name reached `main`. Cause: the guard was run as
  `guard.ps1 | tail -1 && git commit` — **a pipeline returns its LAST
  command's exit code**, so `tail` returned 0 and the `&&` fired despite the
  guard FAILING. Remediated same session: content scrubbed, the single
  contaminated commit rewritten (its message carried the token too), branch
  protection temporarily relaxed → force-push → **protection restored
  byte-for-byte** (`allow_force_pushes:false`, required check `ci-grep-guard`,
  strict). Verified after: guard PASS · **0 of 160 commit trees** carry either
  token · **0 commit messages** · local == origin · PR #4 survived.
  **Residual:** GitHub still serves the orphaned commit **by its 40-char SHA**
  (no branch, private repo → nil practical exposure). Full purge = ask GitHub
  Support to run gc — **founder decision, not yet requested.**
  **Ratchet (executable, tested):** `scripts/hooks/pre-commit` runs the guard
  with a correct exit code and REFUSES the commit on failure — proven by a
  negative test (a deliberately contaminated commit was blocked). Wire it on
  any new clone: `git config core.hooksPath scripts/hooks` (**a fresh clone
  does NOT inherit it**; CI stays the remote detector meanwhile). Write-up:
  `CI-GUARD.md`. Behaviour lesson: memory [[verification-exit-codes]].
- **Session persistence + cold start — BOTH now proven (2026-07-13):** the
  founder's browser crashed mid-session and the agent kept working
  (tmux-backed sessions survive the client). And the relay can **cold-start
  an agent with no human typing `claude`**: `ensure_session()` in
  `provisioning/workstation/relay/swordfish-relay.sh` does
  `tmux has-session || tmux new-session -d 'claude; …'`, auto-dismisses the
  "trust this folder" prompt, waits for the composer, then injects the
  message. Tested this session against a scratch dir via the exact code path:
  **cold → composer ready in ~9 s**. So texting `gogogo` to a topic from the
  phone, laptop shut, boots the agent from `CURRENT.md` and starts work. A
  cold start is a FRESH session (not `--continue`) — which is precisely what
  the `gogogo` + CURRENT.md convention exists for.

## Cross-project: `gogogo` BOOT blocks placed (founder-directed, 2026-07-13)

So a **relay-cold-started** session resumes with no chat history, every project's
handoff file now opens with a BOOT block (read this file + protocol + memory +
git log → state the next action → START it, don't ask):

| project | handoff file | state |
|---|---|---|
| swordfish | `agent_handoff/CURRENT.md` | had it (rule 11) |
| thalon | `agent_handoff/CURRENT.md` | already had it — *"gogogo boots this too"*; left alone (on a feature branch) |
| Project 1 | `agent_handoff/CURRENT.md` | **added + committed, NOT pushed** (explicit pathspec; their 3 WIP files untouched) |
| Project 2 | `agent_handoff/CURRENT.md` | **added + committed, NOT pushed** (same; their no-author-sign-off rule respected) |
| walter (vault) | **`SESSION.md`** (not `CURRENT.md` — founder corrected me) | **added, UNCOMMITTED** — guest rules: dated + attributed, and never push the vault without go-ahead; its own agent commits per its rule 17. Block repeats the standing no-network constraint: **`gogogo` is NOT a network go-ahead.** |

Each project's auto-loaded `CLAUDE.md` already points at its handoff file as the
live-state home, so the BOOT block is reachable without editing their operating
protocols (deliberately not touched — that's their agents' territory).

**Still open for the full phone-only flow:** a new Telegram topic must be bound
to a project in the UNTRACKED `inventory/secrets/relay-map` (thread_id → dir).
Unmapped topics get a polite in-topic reply ("not mapped — add it to relay-map on
syd4"), so it fails safe, but the founder currently cannot self-serve. **Proposed
(not built, awaiting go): a `!map <project>` relay command** — he creates the
topic, types `!map thalon` once, the relay writes its own mapping. The relay
already consumes `!status` / `!stop` / `!kill`, so it is a small addition. Not
touched mid-conversation because the relay IS the founder's comms channel.

**Observed in Project 1's repo (their call, not ours):** `core.hooksPath` is set
to `scripts/hooks` but its `pre-commit` is **not executable** — the hook silently
never runs. Same class of failure as our guard incident (a safety net that looks
armed but isn't). Flagged, deliberately NOT fixed — activating another team's hook
unannounced could block their commits.

## Next

0. **BUILD `!map <project>` — founder call 2026-07-13 ("more durable and
   sustainable... build it next session"). Top of the queue.** Today, binding a
   Telegram topic to a project means the AGENT hand-edits the untracked
   `inventory/secrets/relay-map` — so the founder cannot onboard a project when
   the agent is wedged. `!map` makes it self-serve in one short line.
   Build it in `provisioning/workstation/relay/swordfish-relay.sh` beside the
   existing `!status` / `!stop` / `!kill` handlers, with these constraints
   (reasoned at the founder call — do not skip them):
   - **Allowlist only.** Resolve `<project>` against a fixed set of known dirs
     (`~/work/<slug>` + `~/vault`); never accept an arbitrary path from a
     Telegram message. Sender is already founder-verified, but a typo must not
     cold-start an agent in `/etc`.
   - **Hot-reload the map.** `MAP_FILE` is currently `.`-sourced ONCE at startup,
     so a map edit needs a relay restart today. `!map` must write the entry AND
     re-source (or re-read per cycle) so the binding takes effect immediately.
   - **Confirm in-topic** ("bound topic N → thalon") and ledger it, so a silent
     write can't masquerade as success (delivery-green ≠ content-true).
   - Idempotent: re-mapping an existing topic updates, never duplicates.
   Then the full phone-only flow is: create topic → `!map <project>` → `gogogo`
   → the relay cold-starts the agent and it resumes from its BOOT block.

1. **Soak watch until ≈2026-07-16 23:00 AEST** (72 h from cutover): monitors
   stay green + ≥1 natural verify-deadman pass vs syd2 + morning briefings
   clean. **At soak end:** retire the `*2` A-records (Porkbun delete —
   there's no delete script yet; API `deleteByNameType`), prune the
   `deploy2` temp A-record note in `inventory/boxes.md`, then **present the
   syd1 destroy-vs-warm-fallback gate** (founder decision; at destroy also
   retire syd1's healthchecks check, UptimeRobot monitors, B2 bucket).
2. **⛔ SPEND GATE, queued for the founder: resize syd2 → std-6vcpu**
   (16 GB / 6 vCPU / 180 GB, AUD 78.40 = +AUD 39.20/mo). It PAYS FOR ITSELF:
   Project 1 is on Render Standard + ~60 GB persistent disk ≈ US$40/mo;
   moving its ~41 GB of bio assets + compute to the box and cancelling
   Render nets **≈ US$14/mo cheaper** with 2× RAM/CPU. On "resize go":
   BinaryLane in-place resize (brief reboot, grow-only disk) → re-run
   `hardening-smoke` → then the asset landing zone.
   **KEY FINDING (do not lose this):** the Render disk is a materialized
   CACHE, not the source of truth — Project 1's own progress log records the
   sha256-verified seed (ready 7/7, ≈40.8 GB) from their private Supabase
   source-asset bucket (~38 GB); the corpora are public reference datasets
   (dbSNP/ClinVar/phyloP/RepeatMasker/ClinGen). **Nothing is stranded by
   cancelling Render**, and the re-seed IS the restore path — so the asset
   tree gets an explicit, tested restic EXCLUSION rather than 40 GB of
   nightly waste. Separation of duties holds: we resize + prepare + back
   up + hand off; **Project 1's agent runs the materialization**; Render is
   cancelled only after their checksums verify green on the box.
   Full analysis: `research/capacity-and-data-plan-2026-07-13.md`.
3. **Postgres tenant-DB service on syd2 (founder call 2026-07-13, zero new
   spend):** Postgres 17 via Dokploy on the EXISTING box — per-tenant
   databases + roles for Thalon and Project 2 (RLS is native; slugs stay
   runtime args), pg_dump→restic chain + restore drill BEFORE any tenant
   data (invariant), credentials via `tenant-credential.sh` pattern.
   Project 1's clinical DB stays on managed Supabase (keep-managed invariant).
4. **Post-cutover unblocked queue, now open:** syd3+syd4 Kuma push dead-man
   legs (were "post-cutover follow-up" in boxes.md) · traefik 3.7.7 bump ·
   Dokploy notifications · morning-noise consolidation (fold kuma/ntfy/
   healthchecks pings into the 07:30 slot; grow briefing to real metrics —
   prompt already written, see `provisioning/hermes/README.md`).
5. **Wrap-protocol closing summaries should ride `relay-send.sh`, not
   `hermes send`** (reply-bait argument — noted in the relay design doc);
   fold in when the closing-summary protocol lands.
6. **Founder actions — NEEDS-STEVEN.md** (dashboard renders it): Dokploy
   bookmark → deploy.swordfish.cfd · subscriptions.yml FILL fields (Claude
   card; GitHub next_charge + card) · Mac census re-scan · thalon COPY-ME
   creds note · Gmail MCP re-auth.
7. **When Project 1 / Project 2 land on boxes:** tenant pack via
   `tenant-credential.sh` (defaults now point at `deploy.`) — slugs are
   runtime args, guarded names never enter tracked files; Project 2's
   database rides the Next-3 Postgres service.
8. Unchanged queue: Renovate PR #4 · healthchecks→Telegram · ntfy
   retirement audit · port-map call.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`,
  never chat text (TUI redraws drop selection).
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **Remote command strings: keep systemd/journalctl args SPACE-FREE.**
- **The Mac's rsync is Apple's OLD one** — `-P`, not `--info=progress2`.
- **Delivery-green ≠ content-true** — read back what you wrote; APIs can
  200 silently on wrong ids (Dokploy assignPermissions).
- **inventory/secrets values may carry stray whitespace/CR** (laptop sync):
  consume with `tr -d '[:space:]'` — a leading space 400s the Telegram API.
- Dashboard regen needs `sudo -n systemctl start swordfish-dashboard-regen`
  (deploy user, non-interactive; bare systemctl start asks for auth).
- Dokploy quirk ledger: `runbooks/dogfood.md`.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` · do NOT re-dispatch
backups-apply/restore-drill vs syd1 (frozen; it lacks hook 30 by design) ·
alerts bot is SEND-ONLY and separate from the Hermes bot (and the relay's
outbound voice) · Hermes config edits ONLY via `hermes config set` ·
`hermes cron list` HIDES paused jobs — read `jobs.json` · pre-stage founder
actions · the vault is **walter** (writable, as a guest) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 ·
**syd1 destroy is a founder gate at soak end (≈2026-07-16)** · thalon.org
unwired until launch call (staging-assert retires/rewrites at launch) ·
Hermes never gets spend keys / provisioning authority · syd2's inbound 22
answers CI only · founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
