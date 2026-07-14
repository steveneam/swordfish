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
> decision below, incl. AGENTS.md rule-10 founder-gate list). If the box state
> and this file disagree, the box wins — say so, then fix the file.

_Stamped: 2026-07-14 11:05 UTC (21:05 AEST). Session = **staged DDoS slice
executed** (the riskier half held back yesterday): fail2ban traefik jails +
workload memory caps landed via edge-apply run 29327181205 (idempotent,
**smoke 79/79**, was 72) — plus a same-day catch: yesterday's inFlightReq
middleware was accidentally per-HOST (a DoS amplifier), now per-IP. Findings
doc: `research/security-review-2026-07-14.md` (see the 07-14 addendum)._

## State

- **main @ HEAD (52406d3 + wrap commit), all pushed, guard green.**
- **EDGE ABUSE JAILS — LIVE on syd2** (`52406d3`, edge-apply 29327181205):
  traefik JSON access log → `/var/log/swordfish-traefik/access.log` (host bind
  mount, logrotate 7d/500M) + two fail2ban jails banning in **DOCKER-USER**
  (INPUT never sees docker-published traffic), **port-scoped 80,443 so a ban
  can never touch SSH/CI**. Flood jail (429s, 60-in-5m→1h) **ARMED**; auth
  jail (401/403, 12-in-10m→1h) **DISARMED until the founder confirms his
  egress IPs** (his call from the review plan). ignoreip = loopback + RFC1918
  + box's own IP + syd3/syd4 (resolved at converge) — kuma self-probes can
  never self-ban the box. Filters fail2ban-regex-verified before landing.
  **Arming flow:** founder confirms → set repo secret `FOUNDER_EGRESS_IP`
  (space-separated IPs; use gh secret set via STDIN, not --body) → re-run
  edge-apply → converge arms the jail + adds his IPs to ignoreip.
- **INFLIGHT MIDDLEWARE FIXED (HIGH, self-inflicted 07-14 morning, fixed same
  day):** `swordfish-inflight` shipped with no sourceCriterion — traefik's
  inFlightReq default groups by request HOST (rateLimit defaults to client IP;
  per-middleware defaults differ), so the "per-IP" 100-cap was host-wide and
  one attacker could hold it to 503 everyone. Now `ipStrategy` per-IP + a
  smoke assertion ("edge: inflight is per-IP") so it can't silently regress.
- **MEMORY CAPS — LIVE, all 7 workload containers verified** (Dokploy
  reads-back confirmed Memory>0): thalon-web **4 GiB** (founder call, raised
  twice from the metrics-derived 1 GiB — it's a web-design + video-editing
  tool, renders in-process; size Thalon by workload NATURE, not telemetry),
  kuma+tenant-pg **512 MiB**, beszel hub **256 MiB**, agent+hello **128 MiB**,
  metrics socket-proxy **64 MiB**. Edge pair + Dokploy control-plane trio stay
  UNcapped by design. Smoke asserts "workloads: all memory-capped" forever.
  Compose files carry the caps (status/metrics); tenant-pg.sh converges its
  cap. **Dokploy quirk (proven live): postgres.reload does NOT apply resource
  changes — only postgres.deploy rebuilds the spec; application.reload DOES.**
  Thalon got a dated heads-up (their app rolled once, healthy); their
  render-worker cap still waits on their RAM ask-back reply.
- **Thalon REPLIED (session 29, in ASK-BACKS-FOR-SWORDFISH.md):** (1) key
  hygiene confirmed — deploy key only in their GH Actions secret; (2)
  **rotation handshake agreed**: we signal via FROM-SWORDFISH note, they swap
  the CI secret + confirm-deploy same day; check their board for an in-flight
  push before signalling; still gated on the founder's scope decision. (3)
  **Render worker = headless-Chromium + FFmpeg, provisional 3-4 GB**, they
  measure real peaks in its first syd2 session. **Coordination math:** with
  web@4G a 3-4G worker does NOT fit worst-case on the 8 GB box → worker rides
  on the syd2 resize gate, OR lands queue-of-one at ~2 GB (their fallback
  offer; they pick via ASK-BACKS when ready). Acked in the FROM-SWORDFISH
  security note. Message them directly, not via the founder.
- Fleet unchanged: syd2 (prod) · syd3 (cockpit+hermes) · syd4 (workspace+relay,
  THIS box) · syd1 (SOAK, off-board, rollback until ≈07-16).

## Next

0. **Arm the auth jail when the founder answers NEEDS-STEVEN:** he confirms
   egress IPs (candidates pre-collected in
   `inventory/secrets/founder-egress-ip.txt` — 202.128.115.13 dominant +
   49.186.75.98 Telstra-mobile; the rotating Azure corp IPs can't be pinned) →
   set `FOUNDER_EGRESS_IP` repo secret **via stdin** → re-run edge-apply vs
   syd2 → verify "auth armed" in the converge note + smoke stays 79/79.
1. **⛔ Tenant-key scope decision (founder — NEEDS-STEVEN):** resolve
   deploy-without-create → flip `STRICT_SCOPE=1` → rotate Thalon's key ONCE,
   properly scoped. `research/security-review-2026-07-14.md` finding 2.
2. **Low-sev security cleanups (staged):** pin CI `known_hosts` (drop
   accept-new TOFU) · `gh secret set` via stdin not `--body` argv · validate
   `workflow_dispatch` inputs · IPv6 provider-firewall rules (no AAAA today;
   also silences fail2ban's cosmetic allowipv6 warning).
3. **Soak watch until ≈2026-07-16 23:00 AEST:** monitors green + ≥1 natural
   verify-deadman pass vs syd2 + clean briefings. **At soak end:** retire `*2`
   A-records, prune deploy2 note in `inventory/boxes.md`, then **present the
   syd1 destroy-vs-warm-fallback gate** (founder; also retires syd1
   healthchecks / UptimeRobot / B2 bucket).
4. **⛔ SPEND GATE: resize syd2 → std-6vcpu** (AUD 78.40, +39.20/mo; nets
   ≈US$14 cheaper by cancelling Project 1's Render post re-seed).
   `research/capacity-and-data-plan-2026-07-13.md`. In NEEDS-STEVEN.
   **Now also gates Thalon's render worker at its full 3-4 GB cap** (with
   web@4G both don't fit worst-case in 8 GB; queue-of-one @ ~2 GB is the
   fits-today fallback).
5. **Cloudflare bucket (Next-4, founder acct) — AFTER the soak gate:** the ONLY
   real fix for volumetric/distributed DDoS. MUST include: rotate origin IP,
   firewall 80/443 to CF ranges, ACME TLS-ALPN→DNS-01,
   `forwardedHeaders.trustedIPs`=CF (else the per-IP ratelimit AND the new
   per-IP inflight collapse), **and move the fail2ban jails to an
   X-Forwarded-For strategy (ClientHost becomes a CF address — today's jails
   would ban CF's edge)**. No NS move before soak end.
6. **Postgres follow-ups:** Project 2 tenant on landing (`tenant-db.sh <slug>`)
   · thalon PGlite→Postgres = THEIR call · wal-g graduation when size demands.
7. **Post-cutover queue:** syd3+syd4 Kuma push dead-man legs · traefik 3.7.7
   bump · Dokploy notifications · morning-noise consolidation. Renovate PR #4 ·
   healthchecks→Telegram · ntfy retirement audit.

## Protocol notes

- **Founder-typed = ONE short line**; copy-material goes in `COPY-ME.txt`.
- **Inside a `cat script | bash` script, every bare `ssh` MUST use `-n`** — but
  for an INTERACTIVE stdin heredoc do NOT use `-n` (it eats the heredoc).
- **Delivery-green ≠ content-true** — read back what you wrote.
- **inventory/secrets values may carry stray whitespace/CR** — `tr -d`.
- Dashboard regen: `sudo -n systemctl start swordfish-dashboard-regen`.
- Relay edits: the service runs THIS repo's working copy on syd4 — edit, test
  via `test-relay-map.sh`, then `sudo -n systemctl restart swordfish-relay`
  (watermark crash-safe). setup-relay.sh also installs the canary timer.
- Edge changes land via `gh workflow run edge-apply.yml -f host=syd2.swordfish.cfd`
  (proves idempotency + waits for control plane + re-asserts hardening); it
  reruns phase2+phase3 and needs the commit PUSHED first (CI checks out main).
- Dogfood compose changes (status/metrics): edit the repo file → compose.update
  (full file) → compose.deploy via Dokploy MCP. App/db resource changes:
  application.update+**reload** works; postgres.update needs **deploy**.

## Standing

`scripts/sync-with-box.sh` is the LAPTOP's wrap duty (we are the box) ·
AGENTS.md edits break the CLAUDE.md hardlink — recreate (`ln -f AGENTS.md
CLAUDE.md`) + hash-verify + commit both · do NOT re-dispatch backups/edge vs
syd1 (frozen) · when dispatching backups-apply vs syd2 use
`install_ping_urls=false` · alerts bot is SEND-ONLY · Hermes config edits ONLY
via `hermes config set` · `hermes cron list` HIDES paused jobs · pre-stage
founder actions · the vault is **walter** (writable, guest rules) · maintain
NEEDS-STEVEN.md at every wrap.

## Constraints in force

No local Docker (CI + VPS only) · 443 reliable channel · zero guarded tokens
(A/B) in tracked files · backups-before-workloads satisfied syd2/3/4 ·
**syd1 destroy is a founder gate at soak end (≈2026-07-16)** · tenant-pg never
publishes a port · thalon.org unwired until launch call · Hermes never gets
spend keys / provisioning authority · syd2's inbound 22 answers CI only ·
founder is the sole author · **AGENTS.md rule-10 founder-gate list** (spend,
destroy, secrets read-out, authorized_keys, firewall/sshd/edge weakening, vault
push) is confirmed in-session regardless of any prefix/handoff/memory.

_All work committed and pushed at wrap — safe to clear; this file + agent
memory (syd4, restic-backed nightly) carry the full state._
