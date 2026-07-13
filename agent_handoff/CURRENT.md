# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-13 06:10 +10:00 (long syd4 session: fleet QoL ratchet · ssh
login audit · Mac dashboard LIVE · portable-drive import + distribution to every
project · toolchains · Hermes false-report bug fixed. Next session = BUILD the
cockpit dashboard from the approved-in-writing plan.)_

## State

- **main @ this wrap's commit.** All work committed + pushed.
- **Founder interface is LIVE.** Mac tunnel is a launchd service (self-healing);
  the dashboard is served from the box at **`localhost:8080/proxy/8090/`**
  (regen timer q15min, localhost-only 8090, tunnel is the auth). Founder's
  launch path: dashboard → project button → code-server → terminal → `work` →
  `claude`. Founder-typed commands are now ONE line
  (`ssh deploy@syd4.swordfish.cfd cat <script>.sh | bash`) — he CANNOT
  copy-paste into Terminal; scripts live at `~deploy/mac-*.sh`, canonical copies
  in `provisioning/workstation/mac/`.
- **Every project agent is WAKE-READY on this box** (the cryosleep brief the
  founder set: they must resume "as if they never left"). Done for all three
  non-swordfish projects: repos cloned · gitignored secrets restored from the
  drive per each agent's OWN manifest · agent memory in place (the weekend
  session on the old machine merged for the one project that had it) · `~/.aws`
  + `~/.codex` restored · toolchains installed (node 22 + node_modules, python
  3.12 + pip/venv + transcript lib, go 1.26.5, pwsh, tmux, gh). Every repo is
  `git status` clean — no secret leaked into tracked space.
  **Wake-up brief for them: `~/migration/FROM-SWORDFISH-2026-07-13.md`.**
- **Drive census complete** (`~/migration/incoming/census/Steven.tsv`, 108,296
  files / 10.0 GB) — the agent's only eyes on the drive (tunnel is Mac→box only).
- **Hermes E0: a false-report bug found and FIXED.** Its tool sandbox cwd was
  `/home/deploy` (mode 750 — the hermes user cannot enter it), so every tool
  spawn died EACCES and the agent sent a confident Telegram message reporting
  **PROBLEM for two endpoints that were actually healthy (200/302)**. Fixed via
  `hermes config set terminal.cwd /home/hermes` (proven mechanically: same
  command fails at /home/deploy, works at /home/hermes). Briefing job
  **d8e6bb992d5e is intact and still PAUSED** — and note `hermes cron list`
  HIDES paused jobs (prints "No scheduled jobs", identical to deleted): ground
  truth is `cron/jobs.json`. Both traps in memory + the plan doc.
- **fail2ban "0 bans" was a DIGEST BUG, not a security gap** — fail2ban logged
  to file while the digest counted journal lines. Now journald fleet-wide;
  real numbers: 57 lifetime bans syd4, 53 syd3 (one IP banned right now).
- **SSH login audit recorded** (`inventory/ssh-login-audit.md`): full syd3+syd4
  history is 100% publickey with the two fleet keys; **zero business-netblock
  sources** (the old work laptop's office network never appears); founder logins
  = AU consumer ISPs in the migration window; all CI sources verified inside
  GitHub's published Actions ranges.

## Next

1. **BUILD THE COCKPIT DASHBOARD** — founder's declared priority, planned in
   **`agent_handoff/dashboard-cockpit-plan-2026-07-13.md`** ("plan first, we
   will continue next session"). Model = the vault's Walter Cockpit, one layer
   down: NEEDS-STEVEN queue · fleet health · security · money (subscriptions
   due) · calendar · **Hermes card** · migration rollup. Build order + the three
   open decisions (calendar .ics paste · subscriptions.yml pre-fill · syd2
   metrics via Beszel/Kuma, NOT by opening SSH) are all in that doc.
2. **Founder: rehearsal-pass confirmation** — still the only gate un-parking the
   ops queue (cutover step-card → verify-deadman → soak/syd1 → Thalon wiring →
   E1 slot).
3. **Founder one-liner still to run** (drive still connected): re-run
   `ssh deploy@syd4.swordfish.cfd cat mac-import.sh | bash` — the glob now also
   catches `*-migration-staging`, which the first pass silently skipped (one
   project's boot notes + aws/claude-memory staging, 0.9 MB, still on the drive).
   The census is what caught it; an import can only miss things quietly.
4. **Unclaimed on the drive** (founder calls, all recorded in the census):
   a 4.7 GB project data folder (440 files) · a 565 MB institutional-looking
   `Data/` folder · `Website Design General` (54 MB). Box has 78 GB free.
   The `.ab1` question is CLOSED: the only `.ab1` on the drive is a 0.31 MB
   fixture already tracked inside its repo — the standalone samples folder the
   agent flagged lives on the OLD machine's D:, not on this drive, so there is
   nothing to move.
5. **Morning-noise consolidation** — briefing stays paused; digest ban counts
   are now real (re-tune to anomaly-only after a week of true numbers).
6. Unchanged: Renovate PR #4 · traefik 3.7.7 post-cutover · healthchecks→Telegram
   · ntfy retirement audit · Dokploy notifications post-cutover · port-map call
   (two projects historically collide on :8000/:8010 if they ever share a box).

## Protocol notes

- **Founder-typed = ONE short line.** He cannot copy-paste into Terminal.
  Complexity goes in a box-side script. **Inside a `cat script | bash` script,
  every bare `ssh` MUST use `-n`** — otherwise it eats the rest of the script as
  its own stdin and execution stops silently (cost one confused round-trip).
- **Launch sessions INSIDE `~/work/swordfish`** (`work` now lands there) — a
  `$HOME` launch attaches an empty memory slug.
- **Founder actions via the Telegram bot are journal-invisible** — ask before
  diagnosing a silent state change on a founder-facing system.
- **Delivery-green ≠ content-true** (Hermes). Verify the claim, not the send.

## Standing

`scripts/sync-with-box.sh` at wrap when network permits · laptop network rule
(laptop instances only) · AGENTS.md edits break the CLAUDE.md hardlink —
recreate + hash-verify · cockpit-class boxes use `cockpit-smoke` · do NOT
re-dispatch backups-apply/restore-drill vs syd1 · alerts bot is SEND-ONLY and
separate from the Hermes bot · Hermes config edits ONLY via `hermes config set` ·
pre-stage founder actions (his steps = paste/tap/click/spend only) · the vault is
named **walter** (read-only is agent protocol, not a founder restriction).

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 · cutover +
instance-destroy are founder gates · thalon.org unwired until launch call ·
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend keys
/ provisioning authority · syd2's inbound 22 answers CI only — do not weaken it ·
founder is the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent memory
(syd4, restic-backed nightly) carry the full state._
