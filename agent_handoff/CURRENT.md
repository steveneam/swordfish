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
> Stop only at a founder gate (spend · cutover · destroy · anything named a
> founder decision below). If the box state and this file disagree, the box
> wins — say so, then fix the file.

_Stamped: 2026-07-13 22:25 +10:00 (rehearsal-pass CONFIRMED by founder — ops
queue UN-PARKED; hermes telegram tool hole found and closed; alerts voice
live.)_

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
- **REHEARSAL-PASS CONFIRMED** (founder, this session: "based on the fact
  that you and thalon are running, the migration worked") — the parked ops
  queue is OPEN. Cutover *execution* remains a founder gate; building the
  step-card and verify-deadman is agent work and is now the top of Next.
- **Hermes terminal access: actually closed this session.** The E0 disable
  had only configured the `cli` platform; telegram resolved its composite
  default (= ALL tools) — telegram-side hermes ran nslookup/uname and once
  attempted sudo (blocked by NoNewPrivileges). Fixed with
  `hermes tools disable --platform telegram …`, verified via the gateway's
  own `_get_platform_tools()` resolution, gateway restarted, installer
  ratchet now converges per-platform. Details: design-doc addendum 2 +
  hermes-e0-traps memory.
- **Founder housekeeping cleared:** subscriptions.yml Claude entry filled
  (AU$34/mo Pro incl GST; next_charge 2026-08-13 ASSUMED from "on pro now"
  — correct from receipt); drive .txt deletion declared done; Swordfish-
  topic relay re-confirm exercised (his "Ok" injected mid-turn; reply rode
  the Stop hook). Gmail MCP token EXPIRED — needs founder re-auth before
  receipt lookups work.
- **DRIVE CLEARED TO RETIRE** (census → rescue → verify → backup, all
  closed 2026-07-13): census `Steven.tsv` (108k files) mapped every folder
  to a verified box-side home; the ~130 MB of drive-only gitignored
  research data inside the two ship-first projects' repo folders was
  rescued by the founder's one-liner to `~/migration/incoming/drive-ark/`,
  verified file-complete against the census (gaps = excluded .pyc only;
  extras = .git dirs the census skipped), pointer notes left UNTRACKED in
  both projects' `agent_handoff/FROM-SWORDFISH-DRIVE-ARK.md` for wake-up,
  and captured in manual restic snapshot `94a347f4` (whole-home syd4 set;
  nightly continues). subscriptions.yml: GitHub = Pro US$4/mo (founder);
  next_charge/card fields still FILL.
- **E1 finding-e CLOSED (this session):** the queued "config-silence hermes
  via allowed_chats" was **refuted by adapter source** (v0.18.2 IS the
  latest upstream): reply-to-bot/@mention dispatch has no toggle, and
  excluding the group from `TELEGRAM_ALLOWED_CHATS` also kills observation
  (observe allowlist = `group_allowed_chats ∩ allowed_chats`; state.db has
  no pre-gate inbox → unstored messages are invisible to the poller = eaten
  founder messages). **The ratchet is identity, not config:**
  `provisioning/workstation/relay/relay-send.sh` sends ALL relay outbound
  (Stop-hook replies, poller notices, !cmd responses, fallback sweep) as
  the send-only **alerts bot**, so a founder reply to a relayed message can
  never match hermes's reply-to-bot trigger. Hermes env/config untouched —
  its observe wiring stays exactly as designed; never "fix" this with
  allowed_chats. Until the founder adds `@Swordfish_alerts_bot` to the ops
  group, relay-send falls back LOUDLY to `hermes send` — fallback path
  verified live E2E this session (expected 400 → journal line → delivered).
  **Founder added the bot the same evening; the switch is CONFIRMED live**
  (next send went alerts-voiced, no fallback). Caveat discovered while
  verifying: **Telegram reactions never reach the relay** (hermes doesn't
  subscribe to message_reaction updates) — founder told in-topic to type,
  not tap, when he wants an agent to act. Full semantics: dated notes at
  the end of `agent_handoff/hermes-e1-relay-design-2026-07-13.md`. Relay
  service healthy (3 mapped topics).
- **Prior session (see git log 994680e / 1228835):** thalon staging pack
  complete (fixed pin live, double-Basic root-caused, restic+dump chain
  CI-proven, kuma watch through edge auth, scoped CI credential delivered);
  auto-deploy channel generalized to ALL tenants (founder directive); E1
  relay E2E founder-confirmed.
- Fleet: 4 boxes up; syd2 nightly 15:00 UTC carries the thalon volume +
  dump chain.

## Next

1. **THE OPS QUEUE (un-parked): cutover step-card → verify-deadman →
   soak/syd1.** Build the step-card + deadman first; the cutover MOMENT is
   a founder gate (present the card, wait for go). At cutover ALSO:
   re-point `*2` hostnames, retire syd1 from the dashboard
   (`collectors/lib.sh` host lists + its api_box call), thalon's CI
   api_base flips deploy2→deploy (they keep it a repo variable — already
   told), `staging-assert.sh` + `~/.claude.json` dokploy MCP DOKPLOY_URL
   defaults follow.
2. **Morning-noise consolidation:** adopt hermes's daily-briefing cron
   pattern — one 07:30 digest instead of scattered pings (design notes in
   the hermes-cloud research, wrap of 2026-07-12; hermes approvals are
   manual + cron_mode deny — work within that).
3. **Wrap-protocol closing summaries should ride `relay-send.sh`, not
   `hermes send`** (same reply-bait argument — noted in the design doc);
   fold in when the closing-summary protocol lands.
4. **Founder actions — NEEDS-STEVEN.md** (dashboard renders it): Mac
   census re-scan (he said he'll run it now) · thalon COPY-ME creds note.
5. **When Project 1 / Project 2 land on boxes:** same tenant pack via
   tenant-credential.sh — slugs are runtime args, so guarded names never
   enter tracked files; keep Dokploy project names neutral anyway.
6. Unchanged queue: Renovate PR #4 · traefik 3.7.7 post-cutover ·
   healthchecks→Telegram · ntfy retirement audit · Dokploy notifications
   post-cutover · port-map call · Gmail MCP re-auth (founder, when receipt
   lookups become useful).

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
- Dokploy quirk ledger: `runbooks/dogfood.md`.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` · do NOT re-dispatch
backups-apply/restore-drill vs syd1 (frozen; it lacks hook 30 by design) ·
alerts bot is SEND-ONLY and separate from the Hermes bot (and now also the
relay's outbound voice) · Hermes config edits ONLY via `hermes config set` ·
`hermes cron list` HIDES paused jobs — read `jobs.json` · pre-stage founder
actions · the vault is **walter** (writable, as a guest) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 (thalon
chain included) · cutover + instance-destroy are founder gates · thalon.org
unwired until launch call (staging-assert retires/rewrites at launch) ·
rehearsal-pass confirmed 2026-07-13 (ops queue open; cutover moment still a
founder gate) · Hermes never gets spend keys / provisioning authority ·
syd2's inbound 22 answers CI only · founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
