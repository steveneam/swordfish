# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-11 19:55 +10:00 (hotspot session ON THE WORK LAPTOP — the
founder-interface plan's three legs shipped in one day: fleet login alerts LIVE,
dashboard box-side done, Hermes E0 LIVE on syd3. Ops queue still parked on the
rehearsal-pass confirmation.)_

## Which machine is which (read this first)

- **syd4 = the agent's primary home** (`~/work/swordfish`). This session ran on the
  **Windows work laptop (secondary)** over the founder's mobile hotspot — laptop rule
  stands: NO network beyond general websites + GitHub without asking the founder
  first (an earlier egress-22 probe may have tripped an IT alarm). Hotspot sessions
  are founder-approved per session.
- Sync discipline: git is the bus; one active home per project at a time; laptop
  wrap = guard → commit → push → MANIFEST staging refresh (done this wrap, 19:52).
- **Swordfish agent = senior operations manager of the migration for ALL portfolio
  projects** (founder appointment 2026-07-11): owns workstation readiness, per-agent
  secrets restoration, sync discipline, founder interfaces. Thalon's agent was
  briefed at `E:\thalon\agent_handoff\FROM-SWORDFISH-2026-07-11.md` (his repo,
  uncommitted); his first task = inventory his gitignored secrets on the laptop and
  stage to `thalon-migration\` (they never reached syd4).

## Shipped this session (all committed, guard+zizmor green; design =
## `agent_handoff/founder-interface-plan-2026-07-11.md`)

1. **Fleet SSH-login alerts LIVE on syd2/syd3/syd4** — pam_exec hook posts every
   login to the founder's Telegram (@Swordfish_alerts_bot) labeled by WHICH KEY
   (authorized_keys comment; unknown keys shout), 2-min throttle, daily failed-auth
   digest 21:00 UTC. LLM-free by design. Apply/rebuild = `alerts-apply` workflow
   (secrets `ALERTS_TELEGRAM_BOT_TOKEN`/`ALERTS_TELEGRAM_CHAT_ID`; per-box env file
   can never be pinned in cloud-init — markers added). Verified end-to-end ×3 boxes.
2. **Dashboard (Leg 1) box-side done** — `generate-dashboard.sh` ran on syd4
   (5 buttons; output untracked BY DESIGN — guarded dir names). Founder's 5-min Mac
   setup remains: `provisioning/workstation/mac/MAC-DASHBOARD-SETUP.md` (LaunchAgent
   auto-tunnel + file:// start page in Chromium).
3. **Hermes E0 LIVE on syd3** (charter pull-forward, founder call — amendment to log
   at next checkpoint): hermes-agent 0.18.2, non-sudo user, founder-only Telegram
   allowlist (@Swordfish_hermes_bot — DELIBERATELY a separate bot from alerts),
   eyes-only toolset (web/todo/memory/session_search/clarify/cronjob), manual
   approvals, LLM = **openai/gpt-oss-120b via the founder's Vercel AI Gateway**
   (llama-3.3-70b FAILS Hermes tool calling — see the four ratcheted traps in
   `provisioning/hermes/README.md`), morning briefing cron 21:00 UTC (job
   0581352d8f6d, test-fired + founder-received). First founder conversation
   confirmed working. **Rebuild = install-hermes-syd3.sh + fill .env** (tokens live
   in `inventory/secrets/telegram.env` + `hermes-llm.env` — gitignored, synced to
   syd4's clone 2026-07-11 19:53 so they ride the nightly restic backup; note:
   syd3's restic source is /home/deploy, so /home/hermes itself is NOT backed up —
   deliberate, rebuild-from-script is the DR path).

## Next

1. **Founder: rehearsal-pass confirmation** — STILL the gate that un-parks the ops
   queue (cutover → verify-deadman → soak/syd1 → Thalon wiring → Hermes E1 slot).
2. **Founder, when convenient:** Mac dashboard setup (5 min) · re-copy updated
   MACBOOK-CHECKLIST.md to the USB drive · optional B2 download-cap raise.
3. **E1 build (next session, one session):** conversational relay — phone message →
   Hermes (relay command allowlisted) → persistent per-project Claude Code session
   on syd4 (`claude -p --resume`, stream-json back, `--permission-prompt-tool` for
   out-of-fence taps). Design already in the plan doc.
4. **Consolidation follow-ups (founder Q&A 2026-07-11):** healthchecks.io alert
   channel → Telegram (watcher STAYS off-infra — it alerts on ABSENCE of pings,
   Telegram-from-box cannot) · audit + retire ntfy (redundant post-Telegram) ·
   post-cutover: Dokploy notifications → Telegram + dashboard buttons for
   Dokploy/Kuma · **Sentry + PostHog (founder has free accounts) = app-layer, each
   project wires its own; never self-host either on our boxes** — note for the
   Thalon brief.
5. Renovate housekeeping: PR #4 (golang digest) mergeable anytime; traefik 3.7.7
   branch waits for post-cutover edge-apply protocol.

## Standing

- Laptop network rule (above) · AGENTS.md edits break the CLAUDE.md hardlink —
  recreate + hash-verify after · cockpit-class boxes use `cockpit-smoke` (34) ·
  do NOT re-dispatch backups-apply/restore-drill vs syd1 · alerts bot is SEND-ONLY
  and separate from the Hermes bot so a popped workload box can never command the
  cockpit agent · Hermes config edits ONLY via `hermes config set` (CLI rewrites
  the yaml; seds silently no-op) · pre-stage founder actions: his steps are only
  paste/tap/click/spend — the agent pre-makes everything else.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens (A/B)
in tracked files · backups-before-workloads satisfied syd2/3/4 · cutover +
instance-destroy are founder gates · thalon.org unwired until launch call ·
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend keys /
provisioning authority (E-ladder in charter) · founder is the sole author.

_All work is committed and pushed; the staging drive was refreshed 19:52 — safe to
clear; this file + agent memory + the seed carry the full state to any machine._
