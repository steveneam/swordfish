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

_Stamped: 2026-07-13 17:35 +10:00 (crash-recovery session: sessions made
crash-proof · drive fully drained + placed · vault write access granted ·
clipboard verdict. **Next session = BUILD THE COCKPIT DASHBOARD.**)_

## State

- **main @ this wrap's commit.** All work committed + pushed. Guard green.
- **Sessions are now crash-proof — the big structural change.** A session died
  mid-turn last night (bare `claude` in a code-server tab; the window crash
  killed its pty — box never rebooted, no OOM). Fixed at the root:
  **`agent-term`** (`/usr/local/bin/agent-term`, canonical in
  `provisioning/host/setup-qol.sh`, cloud-init lockstep) is now code-server's
  **default terminal profile** — every terminal lands in a **tmux session named
  after its workspace folder**, claude auto-started. Founder clicks a project
  tab and the agent is running; a window/browser crash leaves it alive;
  reopening reattaches. `work` (ssh path) uses the same folder-derived name, so
  both paths converge on ONE session — never two rival agents. Plain shell =
  the "bash" profile. Proven mechanically (pty-killed test client; session +
  claude survived). Recovery for a rare process death: `claude --continue`.
- **Mode B parallel lanes are now crash-proof too** (a founder-opened terminal
  per worktree folder = its own durable session). Told to the three who care:
  `COORDINATION.md` here, thalon's `agent_handoff/FROM-SWORDFISH-2026-07-13.md`,
  walter's `MIGRATION.local.md`.
- **VAULT WRITE ACCESS GRANTED** (founder, 2026-07-13). AGENTS.md rule 6
  rewritten: swordfish may write/edit walter **as a guest under the vault's own
  rules** — dated + attributed + append-style; migration detail only in
  untracked `*.local.md`; **never push the vault without founder go-ahead**.
  Hardlink recreated + hash-verified after the edit. Two guest notes written.
- **The drive is drained.** Project 2's two data folders (440 files / 4.7 GB,
  and 198 files / 566 MB) → its own staging area under `~/migration/`;
  `Website Design General` (15 files; its 4,370-file node_modules was orphaned
  and excluded at source) → `~/migration/thalon-migration/website-design-general/`
  — founder call: it belongs to **thalon**. All counts verified against the
  census. Duplicate `incoming/` copies (from a re-run) verified identical and
  deleted. **Provenance: the founder confirms the big data folder is the
  CLEANED copy** — this supersedes walter's old "employer-sourced, never move"
  flag (both walter's file and that project's prompt now say so).
- **The drive's 9 loose `.txt` resume prompts are consolidated** into each
  project's `agent_handoff/drive-notes/` (verbatim, byte-verified) + folded
  into a fresh `agent_handoff/RESUME-PROMPT-2026-07-13.txt` per project that
  **flags what in their old prompt is now wrong** (restore steps already done;
  and for Project 2, its "data can never reach the VPS / tests skip
  permanently" line is superseded — its data is here and its reproduction
  tests can run). Walter's went to `~/vault/WALTER-RP-2026-07-10.local.md`.
  Swordfish's own + `Files location.txt` → `~/migration/drive-notes-archive/`
  (never tracked: drive layout + secret topology). **Founder is cleared to
  delete the .txts from the drive.**
- **Box→Mac clipboard: OSC52 FAILED on the founder's browser.** The box emits
  the correct sequence (`copy`/`copytest` installed, tmux passthrough on) but
  his Chromium/code-server does not deliver it. **Working convention:
  `COPY-ME.txt` at the swordfish repo root (gitignored)** — the agent writes
  copy-material there, the founder clicks it in the file list and copies from
  the editor (selection never drops there). MAC-COMMANDS.txt §6 says so.
- **mac-data.sh is placement-aware**: placing a folder empties `incoming/`,
  which silently turned "safe to re-run" into "re-uploads 5.3 GB". It now reads
  box-side `incoming/.placed` and skips placed folders. **Every future
  placement must append to that list.**
- **Google Calendar secret .ics is stored + live-tested** (49 events) at
  `inventory/secrets/google-calendar-founder.ics.url` (gitignored). The cockpit
  calendar card needs no OAuth.
- **Telegram login alerts are working as designed** — the founder's one-liners
  fire several (script fetch + control calls + rsync); today's are 100%
  `deploy from <his IP> key: swordfish-ops`. An `UNRECOGNIZED-KEY` line is the
  alarm; today there are none.

## Next

1. **BUILD THE COCKPIT DASHBOARD** — founder's declared priority, planned in
   `agent_handoff/dashboard-cockpit-plan-2026-07-13.md`. Calendar decision is
   now CLOSED (secret stored). **One open decision left:** may swordfish poll
   the infra billing APIs read-only + pre-fill `subscriptions.yml` for the
   founder to correct once. (syd2 metrics come from Beszel/Kuma — never by
   opening SSH from the cockpit.)
2. **Founder: rehearsal-pass confirmation** — still the only gate un-parking
   the ops queue (cutover step-card → verify-deadman → soak/syd1 → Thalon
   wiring → **E1**).
3. **E1 relay, design now fixed by the founder** (2026-07-13): Hermes must open
   a project **in the same crash-proof folder-named tmux session** ("as if I
   opened the VS Code folder myself") and relay his message to that project's
   agent, reply back per-project. Mechanism sketch + constraints in memory
   (`hermes-e1-relay-directive`): inject via `tmux send-keys`, read the reply
   from the project's transcript JSONL; Hermes never gets spend keys or
   provisioning authority.
4. **Census re-scan at the end of the cockpit-build session** (founder ask) —
   the final "nothing left behind" check before the drive retires. Current
   census: `~/migration/incoming/census/Steven.tsv` (108,296 files).
5. Unchanged: morning-noise consolidation · Renovate PR #4 · traefik 3.7.7
   post-cutover · healthchecks→Telegram · ntfy retirement audit · Dokploy
   notifications post-cutover · port-map call.

## Protocol notes

- **Founder-typed = ONE short line.** He cannot copy-paste into Terminal, and
  **cannot copy out of the agent's chat window at all** (TUI redraws drop the
  selection) — copy-material goes in `COPY-ME.txt`, never in chat text.
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`.**
- **The Mac's rsync is Apple's OLD one** — rsync 3.x-only flags (e.g.
  `--info=progress2`) error out; use `-P`.
- **Delivery-green ≠ content-true** (the Hermes false-report bug).
- **Founder actions via the Telegram bot are journal-invisible.**

## Standing

`scripts/sync-with-box.sh` at wrap when network permits · AGENTS.md edits break
the CLAUDE.md hardlink — recreate + hash-verify · cockpit-class boxes use
`cockpit-smoke` · do NOT re-dispatch backups-apply/restore-drill vs syd1 ·
alerts bot is SEND-ONLY and separate from the Hermes bot · Hermes config edits
ONLY via `hermes config set` · `hermes cron list` HIDES paused jobs — read
`jobs.json` · pre-stage founder actions (his steps = paste/tap/click/spend
only) · the vault is **walter** (now writable, as a guest).

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 · cutover +
instance-destroy are founder gates · thalon.org unwired until launch call ·
rehearsal-pass confirmation precedes the ops queue · Hermes never gets spend
keys / provisioning authority · syd2's inbound 22 answers CI only · founder is
the sole author.

_All work committed and pushed at wrap — safe to clear; this file + agent memory
(syd4, restic-backed nightly) carry the full state._
