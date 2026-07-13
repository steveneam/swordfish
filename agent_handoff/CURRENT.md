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

_Stamped: 2026-07-13 21:55 +10:00 (E1 finding-e closed: relay outbound now
rides the alerts bot; one-tap founder ask pending.)_

## State

- **main @ HEAD, all pushed, guard green** (git log is the authority).
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
  Full semantics: dated note at the end of
  `agent_handoff/hermes-e1-relay-design-2026-07-13.md`. Relay service
  restarted and healthy (3 mapped topics).
- **Prior session (see git log 994680e / 1228835):** thalon staging pack
  complete (fixed pin live, double-Basic root-caused, restic+dump chain
  CI-proven, kuma watch through edge auth, scoped CI credential delivered);
  auto-deploy channel generalized to ALL tenants (founder directive); E1
  relay E2E founder-confirmed.
- Fleet: 4 boxes up; syd2 nightly 15:00 UTC carries the thalon volume +
  dump chain.

## Next

1. **Morning-noise consolidation:** adopt hermes's daily-briefing cron
   pattern — one 07:30 digest instead of scattered pings (design notes in
   the hermes-cloud research, wrap of 2026-07-12; hermes approvals are
   manual + cron_mode deny — work within that).
2. **When the founder adds `@Swordfish_alerts_bot` to the group:** nothing
   to run — the voice switches per-send automatically. Optionally confirm
   via journal (no more "falling back" lines) and consider routing
   wrap-protocol closing summaries through `relay-send.sh` (noted in the
   design doc).
3. **Founder actions — all in NEEDS-STEVEN.md** (dashboard renders it):
   add alerts bot to ops group · subscriptions.yml correction ·
   rehearsal-pass confirmation (un-parks the ops queue) · drive .txt
   deletion · Mac census re-scan · hermes terminal call · optional
   Swordfish-topic relay re-confirm.
4. **On rehearsal-pass → the parked ops queue:** cutover step-card →
   verify-deadman → soak/syd1. At cutover ALSO: re-point `*2` hostnames,
   retire syd1 from the dashboard (`collectors/lib.sh` host lists + its
   api_box call), thalon's CI api_base flips deploy2→deploy (they keep it a
   repo variable — already told), `staging-assert.sh` + `~/.claude.json`
   dokploy MCP DOKPLOY_URL defaults follow.
5. **When Project 1 / Project 2 land on boxes:** same tenant pack via
   tenant-credential.sh — slugs are runtime args, so guarded names never
   enter tracked files; keep Dokploy project names neutral anyway.
6. Unchanged queue: Renovate PR #4 · traefik 3.7.7 post-cutover ·
   healthchecks→Telegram · ntfy retirement audit · Dokploy notifications
   post-cutover · port-map call.

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
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend
keys / provisioning authority · syd2's inbound 22 answers CI only · founder
is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
