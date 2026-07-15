> **ARCHIVED 2026-07-15** — all three legs BUILT + LIVE: dashboard (v3 collectors, `provisioning/workstation/`) · fleet login alerts (`provisioning/host/setup-login-alerts.sh`) · hermes E1 relay (`provisioning/workstation/relay/`). Leg-3 sketch superseded by `research/hermes-e1-relay-design-2026-07-13.md`.

# Founder interface plan — dashboard · fleet alerts · Hermes E0/E1 (2026-07-11)

One plan, three legs, all serving the same goal: the founder drives the fleet from a
browser (Mac) and a chat thread (phone), with the boxes telling him when anything
unexpected happens. Supersedes nothing; pulls the chartered Hermes pilot forward.

## Founder decisions on record (2026-07-11)

1. **Hermes host = syd3** ("good for now") — bare-metal install on the cockpit, NOT the
   chartered Dokploy/syd2 path. Rationale: syd3 is the cleanest trust boundary for a
   chat-connected agent (no portfolio content), available now without touching the
   parked ops queue, and briefings/triage is cockpit work. **Charter amendment to log
   at next checkpoint:** Hermes E0 lands pre-cutover on syd3; Dokploy/syd2 remains the
   documented graduation path. LLM budget gate already satisfied (Bucket-5 in-flight
   record: Vercel AI Gateway + Groq Llama 3.3-class, US$10/mo hard cap).
2. **Channel = Telegram** (working choice; free Bot API, sender allowlist, long-polling
   = outbound 443 only — fits the reliable-channel rule and inbound-22-only boxes).
3. **Approval UX = near-zero taps, never per step** (see model below). Founder
   clarification (mid-session): the phone channel is CONVERSATIONAL — he directs
   Claude Code on his projects from the phone the way he does at a keyboard, with
   Hermes as the relay. Not one-shot dispatch.
4. **Swordfish agent = senior operations manager of the machine migration for all
   portfolio projects** (founder appointment, 2026-07-11): responsible for the
   workstation (syd4) being fit for every project agent + the founder, and for the
   cross-machine sync discipline.

## The approval / permissions model (answers the founder's question)

Two layers, one tap total:

- **Hermes layer:** Hermes runs exactly ONE kind of command — the relay script that
  feeds the founder's message into a per-project Claude Code session. That command
  pattern is ALLOWLISTED in Hermes (auto-approved) → **zero taps per message**; the
  sender allowlist (founder's Telegram ID only) is the gate on the channel, and the
  relay script is constrained (text into a scoped session, nothing else).
  `approvals.mode: manual` still guards any OTHER command Hermes might ever want.
  Status/progress messages are notifications — approvals never apply to them.
- **Claude Code layer** (on syd4): conversational sessions via headless resume — each
  phone message continues the project's persistent session (`claude -p --resume
  <session-id> --output-format stream-json`), replies stream back to Telegram. Runs
  under the `deploy` user (never root) with a **scoped permission profile**, not
  `--dangerously-skip-permissions`: per-project cwd, allowlisted tools (edits, git,
  build/test inside the project), deny-rules for destructive patterns, isolated
  branch/worktree. Routine work needs NO approval. For actions OUTSIDE the fence,
  use `--permission-prompt-tool` to route the permission request to Telegram as a
  tap — the keyboard experience, on the phone: mostly autonomous, asks only when
  it matters. Session registry (project → session-id) lives with the relay script;
  `/new <project>` starts fresh, `/kill` scoped-kills the session's processes.

What was rejected from the blueprint: `User=root`, chat-triggered
`--dangerously-skip-permissions`, ANSI-scrubbing of TUI output (replaced by
stream-json), OpenRouter free tier (charter's gateway choice stands), `git reset
--hard` via text.

## Leg 1 — Dashboard (browser front door, Mac)

Goal: open Chromium → click a project → VS Code (code-server) opens it. No terminal.

- **Mac side:** a LaunchAgent plist keeps `ssh -N -L 8080:localhost:8080 syd4` alive
  (auto-reconnect, keepalives). One-time install; delivered as a file per the
  "copyable content goes in files" rule (append to `~/migration/MAC-COMMANDS.txt`
  pattern or a new `MAC-DASHBOARD-SETUP.md`).
- **Start page:** static HTML, one button per project → `http://localhost:8080/?folder=
  /home/deploy/work/<project>` (+ vault read-only, + a "cockpit" button for syd3 when
  its code-server lands, if ever). Set as Chromium homepage. Served locally from the
  Mac (file://) — zero new services on the box.
- Security posture unchanged: code-server stays tunnel-bound 127.0.0.1; box stays
  tcp/22-only. Public 443 exposure of code-server stays a rejected-unless-revisited
  option (full shell behind a password).

## Leg 2 — Fleet login/activity alerts (LLM-free, deterministic)

Goal: Telegram message on every SSH session open/close on every box, labeled by WHICH
KEY authenticated (CI runner / founder Mac / break-glass / unknown) + source IP; daily
failed-auth digest. Unexpected key or IP stands out instantly.

- `pam_exec` hook on sshd session events → `pam-notify.sh` → Telegram Bot API over
  outbound 443. No daemon, no LLM, no new attack surface. Key label via
  `SSH_AUTH_INFO_0`/authorized_keys comment mapping.
- Per-box env file (`/etc/swordfish/alerts.env`, 600, root) holds bot token + chat ID;
  provisioned via `alerts-apply` workflow (CI-as-hands), secrets under per-box
  prefixes per fleet convention. Pinned in all cloud-inits (syd2/syd3/syd4; syd1
  skipped — it retires).
- **Response stays human-in-the-loop** at v0: alert + break-glass runbook (kill
  sessions, ufw deny). At E1 Hermes *proposes* response commands; founder approves.
  No auto-banning (lockout risk).

## Leg 3 — Hermes pilot on syd3 (E0 → E1)

- **E0 (eyes):** bare-metal install as dedicated non-root `hermes` user;
  `TELEGRAM_ALLOWED_USERS` = founder's ID ONLY (deny-by-default); terminal tool
  DISABLED; no yolo ever; cron morning briefing (disk/RAM/backup ping/cert expiry
  across the fleet via read-only checks) + triage phrasing of Leg-2 alerts. LLM =
  Vercel AI Gateway key (founder provides at install), Groq Llama 3.3-class.
- **E1 (propose + one-tap dispatch):** enable terminal with `approvals.mode: manual`
  + deny-rules; add the ONE skill: dispatch a Claude Code task to syd4 over SSH
  (dedicated dispatch keypair, syd3 → deploy@syd4; inbound 22 already open to the
  world for CI). Dispatch script on syd4 runs the scoped headless profile above,
  relays stream-json progress → Telegram, ends with summary + branch/PR link.
  Founder kill command: scoped pkill of the dispatch user's claude processes.
- **Verdict gate (charter):** 2–4 weeks at E0/E1 → keep or drop. E2 (constrained
  hands on dogfood workloads) only if E1 earns it. Never: spend-capable keys,
  docker socket, provisioning authority, guarded-token-adjacent content.

## Workstation readiness (senior-ops-manager duties, syd4)

- Each project agent runs a first-boot **gitignored-secrets inventory**; founder
  copies from the drive or re-provisions. **Thalon's secrets are still missing**
  (location was unknown at transfer) — his laptop-side agent enumerates them THIS
  weekend where they exist, stages them to `thalon-migration\` on the drive.
- Dashboard buttons exist for every project dir under `~/work` + vault.
- Sync discipline (one active home per project; git is the bus; wrap = guard →
  commit → push → staging refresh) — briefed to each project agent via their
  `agent_handoff/` (Thalon's brief delivered 2026-07-11).

## Build order & gates

- **Phase 0 (laptop, repo-only — buildable now over GitHub):** author everything:
  dashboard start page + plist + Mac setup sheet; `pam-notify.sh` + `alerts-apply`
  workflow + cloud-init pins; `provisioning/hermes/` install+config script (env
  templates, systemd unit, config.yaml with the security posture baked in).
- **Phase 1 (founder, phone/Mac, ~10 min):** @BotFather bot → token + chat ID into
  the secrets path; Vercel AI Gateway key ready; run the Mac dashboard setup sheet.
- **Phase 2 (box-touching — hotspot or founder-approved dispatch):** alerts-apply
  fleet-wide → verify a login alert fires; Hermes E0 install on syd3 → first morning
  briefing received; dashboard end-to-end test from the Mac.
- **Phase 3 (E1):** dispatch keypair + syd4 dispatch script + Hermes skill → first
  one-tap task end-to-end on a Thalon-scoped test branch.
- Every phase ends with the ratchet: scripts + cloud-init pins committed; nothing
  documentary-only. Network rule stands: nothing box-touching from the work laptop
  without founder approval.
