# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-13 13:55 +10:00 (short syd4 session, launched from the HOME dir —
see the protocol note. Hermes briefing incident diagnosed + resolved with founder
clarification; dashboard Mac setup = founder's declared priority for the next
session; ops queue still parked on the rehearsal-pass confirmation.)_

## State

- **main @ this wrap's commit** (prior: 2540e5b hermes trap 5; before that pulled
  the laptop hotspot wrap 055eb0b — everything the laptop shipped is on this box).
- **Hermes E0 on syd3: healthy, briefing PAUSED by founder choice.** Full timeline:
  the morning-briefing (0581352d8f6d) fired on schedule 2026-07-11 21:00 UTC and
  DELIVERED (founder-confirmed); its gateway session hung afterwards (orphaned
  CLOSE-WAIT to the AI gateway; journal silent from that moment; the 2026-07-13
  restart pruned it as "left by a crashed gateway"). `jobs.json` then emptied at
  2026-07-12 01:36 UTC with no journal trace — initially misread as scheduler
  stale-claim cleanup; **actually the founder stopped the reminder himself from
  Telegram** (clarified 2026-07-13; adapter-level bot commands leave no journald
  lines). Gateway restarted clean; job recreated as **d8e6bb992d5e**, test-fired
  green (founder received it), then **paused at founder request** — resume on syd3:
  `sudo -u hermes hermes cron resume d8e6bb992d5e`. Trap 5 + the verbatim create
  command are pinned in `provisioning/hermes/README.md` (rule-9 gap closed — the
  original create command had lived only in the laptop session).
- **Founder's stated reason for stopping it:** the morning alert digests
  ("syd2/3/4 auth digest 24: N failed/invalid ssh attempts, 0 fail2ban bans") —
  morning-noise consolidation is now a real work item (Next 3).
- **Dashboard Part 1 re-run this session:** `/home/deploy/dashboard/index.html`
  fresh (5 buttons → code-server `?folder=` links, one per project + vault).
- `work` alias on syd4 = `tmux new -A -s main` (attach-or-create; no cd — cd to
  the project before launching claude).

## Next

1. **Founder: rehearsal-pass confirmation** — STILL the only gate un-parking the
   ops queue (cutover step-card presented first, then verify-deadman → soak/syd1 →
   Thalon wiring → E1 slot).
2. **Dashboard Mac setup — founder's declared priority (his call, 2026-07-13):**
   walk him through Parts 2–3 of
   `provisioning/workstation/mac/MAC-DASHBOARD-SETUP.md` (2 scp lines +
   `launchctl load` + file:// start page in Chromium). Part 1 (box side) is done.
   His steps are paste/click only — pre-stage anything further he'd need.
3. **Morning-noise consolidation** (new, from the founder's briefing stop):
   (a) briefing fate — stays paused; revisit resume-vs-remove at the E0/E1 verdict
   gate; (b) tune the daily failed-auth digest toward anomaly-only (every-morning
   counts of routine internet scanner noise is what drove the stop);
   (c) **verify fail2ban is actually banning on syd2/3/4** — digests report
   "0 bans" alongside nonzero failed attempts every day; check jail status
   (failed attempts on key-only boxes are harmless background noise, but 0 bans
   ever is worth one look).
4. **E1 conversational relay** (design in
   `agent_handoff/founder-interface-plan-2026-07-11.md`) — after the dashboard.
5. Unchanged from 2026-07-11: Renovate PR #4 mergeable anytime · traefik 3.7.7
   waits for post-cutover edge-apply · healthchecks→Telegram channel · ntfy
   retirement audit · Dokploy notifications post-cutover · Sentry/PostHog =
   app-layer, never self-hosted.

## Protocol notes (expensive lessons, 2026-07-13)

- **Launch sessions INSIDE `~/work/swordfish`.** A session launched from
  `/home/deploy` attaches an EMPTY memory slug (`-home-deploy`) — the old
  NEXT-SESSION.txt "open /home/deploy" flow caused exactly that this session
  (recovered by reading the memory store manually). Correct launch: `work` →
  `cd ~/work/swordfish` → `claude`. The dashboard buttons already open
  code-server in the right folder per project.
- **Founder actions via the Telegram bot are journal-invisible** — before
  diagnosing any silent state change on a founder-facing system, ask the founder
  first (this session burned ~30 min on a phantom scheduler bug).

## Standing

Carry forward unchanged from the 2026-07-11 wrap: `scripts/sync-with-box.sh` at
wrap when network permits · laptop network rule (laptop instances only) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate + hash-verify ·
cockpit-class boxes use `cockpit-smoke` (34) · do NOT re-dispatch
backups-apply/restore-drill vs syd1 · alerts bot is SEND-ONLY and separate from
the Hermes bot · Hermes config edits ONLY via `hermes config set` · pre-stage
founder actions (his steps = paste/tap/click/spend only).

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 · cutover +
instance-destroy are founder gates · thalon.org unwired until launch call ·
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend
keys / provisioning authority · founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent memory
(syd4, restic-backed nightly) carry the full state._
