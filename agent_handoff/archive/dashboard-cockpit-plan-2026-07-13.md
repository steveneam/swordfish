> **ARCHIVED 2026-07-15** — BUILT as planned: v3 collectors→renderer live (`provisioning/workstation/collectors/collect-*.sh`, all seven cards). Last open item (subscriptions.yml FILLs) tracks in NEEDS-STEVEN, not here.

# Cockpit dashboard — plan (founder ask, 2026-07-13)

_Status: PLAN ONLY — nothing below is built yet. Founder said "plan these first,
we will continue next session". Build order + open decisions at the bottom._

## What exists today (v2, live)

`localhost:8080/proxy/8090/` — one card per project + walter, each showing box ·
branch · last commit · uncommitted/unpushed · files-touched · last agent session.
Regenerated every 15 min by a systemd timer; served localhost-only; reached
through the founder's existing Mac tunnel. Generator:
`provisioning/workstation/generate-dashboard.sh`; installer: `setup-dashboard.sh`.

## The model: Walter Cockpit, for infrastructure

The vault's Walter Cockpit (`.obsidian/plugins/walter-cockpit`) renders a
portfolio command center: status rollup per business · staleness thresholds ·
a **"Needs Steven"** queue of pending approvals/asks · ledger + log. The syd4
dashboard should be the same idea one layer down — the **infrastructure
cockpit** — and its top section should be that same "Needs Steven" queue,
because that is the part a founder actually acts on.

## Sections (top → bottom)

### 1. Header — time + tick
Live clock (JS, no network): **Sydney local + UTC**, today's date, box uptime.
Cheap, and it anchors every stamp below.

### 2. NEEDS STEVEN (the action queue — the point of the page)
One line per open founder action, newest first, each with an age. Sources, all
already on disk, no new plumbing:
- **approval gates** — parsed from `agent_handoff/CURRENT.md` "Next" section
- **spend gates** — any pending box purchase/resize
- **subscription payments due** (see §5)
- **cert / domain expiries** inside 30 days (see §4)
- **agent asks** — the "Needs Steven" lines each project agent leaves in its own
  `agent_handoff/CURRENT.md` (fan out over `~/work/*/agent_handoff/CURRENT.md`)
Rule: an item disappears only when its source says done — the dashboard never
invents state.

### 3. FLEET HEALTH (per box: syd2 · syd3 · syd4, one row each)
disk used/free · memory · load · uptime · unattended-upgrades reboot-pending ·
last restic snapshot age (**red if > 36 h**) · dead-man receiver status ·
services (traefik/dokploy/code-server/hermes as applicable).
- syd4 = local; syd3 = SSH from the cockpit (already works).
- **syd2 is NOT SSH-reachable from the cockpit by design** (inbound 22 answers
  CI runners only). Do not weaken that. Pull syd2's numbers from the monitoring
  that already watches it: **Beszel hub + Uptime Kuma on syd2** (both have APIs;
  read-only token in `/etc/swordfish/`, never in the HTML). If a metric can't be
  had that way, the row says so — a blank is honest, a guess is not.

### 4. SECURITY (fleet)
- ssh login alerts (last N, from journald `swordfish-alerts` tag) — **who / from
  where / which key**, with the key label; anything not matching a known key or
  a GitHub Actions range renders **red**. Ties into `inventory/ssh-login-audit.md`.
- failed-auth counts + **fail2ban bans per box, per 24 h** (the digest now counts
  these correctly — the journald logtarget fix, 2026-07-13).
- ufw posture · sshd key-only assertion · TLS cert expiry per public host
  (traefik/LE) · **domain expiry** (Porkbun API, token already held).
- open CVE-ish signal: `unattended-upgrades` pending + reboot-required flag.

### 5. MONEY (recurring spend + what's due)
Two sources, deliberately separate:
- **API-backed (no founder maintenance):** BinaryLane + Vultr invoices/balance,
  Backblaze B2 usage→cost, Porkbun domain renewals. Tokens exist already
  (`inventory/secrets/`, gitignored) — collectors read them box-side; **the
  rendered HTML never contains a token or an account id**.
- **Founder-maintained (SaaS the box can't see):** a small `subscriptions.yml`
  (name · amount · cycle · next charge · card). I pre-fill it from what's known
  (Claude, GitHub, any AI gateway) and the founder corrects it once.
Renders: monthly run-rate · next 30 days of charges · anything **overdue or
inside 7 days** promotes into §2 Needs Steven.

### 6. CALENDAR (next 5 events)
Google Calendar's **secret .ics address** (Settings → the calendar → "Secret
address in iCal format") pasted once into `/etc/swordfish/calendar.env`. The box
fetches it on the 15-min timer, renders the next 5 events with times. No OAuth,
no Google API project, no MCP dependency — one paste, and it survives reboots.
(An MCP-based route would need an interactive login the box can't hold.)

### 7. HERMES (its own card — yes, it belongs here)
Hermes is fleet infrastructure, so it gets a card like any box:
- gateway state · Telegram connection · channel (the founder's DM)
- **cron jobs read from `cron/jobs.json`, NOT from `hermes cron list`** —
  `cron list` hides PAUSED jobs, so a paused job and a deleted job look
  identical there (trap found 2026-07-13; this is how the dashboard avoids
  repeating the trap-5 misdiagnosis). Show: id · schedule · **paused/active** ·
  last run + last status · next run.
- **last message in** (founder → Hermes) and **last message out** (Hermes →
  founder), each with timestamp + a one-line snippet, read from Hermes's
  `state.db` `messages` table (role/timestamp/content).
- last cron output file, and **whether its content actually verified** — the
  2026-07-13 run "delivered" but reported PROBLEM for two endpoints that were
  in fact healthy; delivery-green ≠ content-true. Card shows both.

**Per-project Hermes threads (the founder's real ask) = an E1 feature, not E0.**
Hermes today is a single-channel ops bot: one Telegram DM, no per-project
routing, so "last message about thalon" cannot be answered honestly from E0
data. The E1 conversational relay (`agent_handoff/founder-interface-plan-2026-07-11.md`)
is where per-project threads land; when it ships, each project card grows a
"last Hermes message" line. Until then the dashboard shows the single channel
and says so, rather than faking attribution.

### 8. MIGRATION / TRANSFER (fades out once complete)
What crossed from the portable drive: bytes + file counts per project, what was
verified gitignored, and **what is still on the drive and unclaimed** (see the
census). Disappears when the drive is retired.

## Implementation shape

- Split the one generator into **collectors → JSON → renderer**:
  `collect-{fleet,security,money,calendar,hermes,projects}.sh` each write
  `~/dashboard/data/<name>.json`; `render-dashboard.sh` composes the HTML.
  A collector that fails writes a `{"error": ...}` and the card renders a
  visible **STALE/UNAVAILABLE** state — never a silently blank panel.
- Timer stays (15 min); the page's own JS ticks the clock and shows the age of
  each data file, so staleness is visible without a refresh.
- Secrets stay in `/etc/swordfish/*.env` (root, 600). Collectors read them;
  rendered HTML never contains them. 8090 stays localhost-only — the tunnel is
  the auth. Nothing new opens in ufw.
- Everything tracked in `provisioning/workstation/`; the rendered HTML stays
  untracked (project names).

## Build order (next session)

1. **Refactor to collectors + renderer** (no new data yet — pure seam).
2. **Fleet health + security** (§3, §4) — highest ops value, all data already
   on-box; syd2 via Beszel/Kuma read-only.
3. **Hermes card** (§7) — jobs.json + state.db, both already readable.
4. **Needs Steven** (§2) — needs §5's due-dates to be complete, so it lands here.
5. **Money** (§5) — API collectors first, then the founder's one-time
   `subscriptions.yml` correction pass.
6. **Calendar** (§6) — one paste from the founder, then done.

## Open decisions (founder)

- **Calendar:** paste the Google Calendar secret .ics address? (one paste, then
  it just works). Alternative: skip the calendar section.
- **Money:** OK to pre-fill `subscriptions.yml` from known SaaS and have you
  correct it once? And confirm the infra APIs (BinaryLane/Vultr/B2/Porkbun) may
  be polled for invoices — read-only, tokens already held.
- **syd2 metrics:** confirmed route is Beszel/Kuma read-only (NOT opening SSH
  from the cockpit to syd2). Say if you'd rather it stay dark.
