# Operational decisions digest

> Slim ops-agent reference. **Canonical source = `CHARTER.md` (pinned-decisions table + buckets)** —
> this page holds only the operational parameters an agent needs mid-task. Link, don't copy.
> No secrets here: key **names** only; values live in gitignored `.env` / `inventory/secrets/`.

## Naming

- Apex domain: **`swordfish.cfd`** (Porkbun; auto-renew on; renewal $15.96/yr).
- Boxes: region + ordinal → `syd1.swordfish.cfd`, `syd2.…`.
- Services (flat, box-independent): `deploy.` (Dokploy) · `status.` (Uptime Kuma) · `metrics.` (Beszel).
- B2 buckets: `swordfish-<box>-backups` (e.g. `swordfish-syd1-backups`).
- **Public-name rule:** TLS hostnames land in CT logs and bucket names are global — the
  guarded-token rule applies to every public infrastructure name. Neutral names only.

## Host/edge parameters (Buckets 1.5–2 implement; Checkpoint-1 amendments)

- Vultr firewall group on every box: inbound 22/80/443 only (Docker bypasses ufw — the
  provider firewall is the layer it can't bypass; ufw stays as belt-and-braces).
- Docker `daemon.json`: json-file log caps (`max-size`/`max-file`). **No `live-restore`** —
  the daemon refuses swarm init with it set (hit live on syd1, 2026-07-07) and Dokploy
  is swarm-based; swarm task restarts + `restart: always` on the edge cover daemon restarts.
- unattended-upgrades reboot window (kernel updates need reboots; no Ubuntu Pro attach).
- Published-ports rule is executable: CI asserts no `0.0.0.0` publishes besides Traefik 80/443.
- GitHub Actions: SHA-pinned only; zizmor lints workflows; Renovate maintains pins.
- Dokploy: version-pinned; never upgrade before its config is in the backup set.
- Rate-limit middleware (Bucket 4+): **public app routers only — never the control-plane
  router** (reachability invariant). Forward-auth SSO: not before box #2 (Checkpoint-2
  amendment 4; adopts at Bucket 6 and must exempt Dokploy API/MCP header-auth routes).

## Edge pins (Bucket 2, applied 2026-07-07 — lockstep: `phase3-edge.sh` · `compose/edge/` · `assert-hardening.sh`)

- **Dokploy `v0.29.10`** (latest stable at build; v0.29.9 was superseded within hours —
  treat same-day double-releases as a smell when re-pinning). Install vendored into
  `phase3-edge.sh`, NOT piped: upstream `install.sh` is destructive on re-run
  (`swarm leave --force`) and aborts if 80/443 are bound. Port 3000 never published.
- **Traefik `v3.6.7`** (digest-pinned; the version Dokploy pairs with) as
  `swordfish-traefik` — never named `dokploy-traefik` (Dokploy force-removes that name).
  TLS-ALPN challenge; JSON logs; no dashboard; no HTTP/3 (firewalls are TCP-only).
- **tecnativa/docker-socket-proxy `0.3.0`** (digest-pinned), `CONTAINERS=1` read-only;
  wollomatic/socket-proxy = documented stricter swap path.
- `postgres:16` / `redis:7` tag-pinned (vendored from upstream install; digest-pinning
  these via a Renovate regex manager = deferred nice-to-have).
- LE email lives in `compose/edge/traefik/traefik.yml` (repo is private; not CT-exposed).

## Backup parameters (Bucket 3, applied 2026-07-07 — lockstep: `provisioning/backup/profiles.yaml` · `phase7-backups.sh` · `assert-hardening.sh`; runbook: `runbooks/backup-restore.md`)

- restic → B2, nightly, encrypted; driven by **resticprofile** (tracked YAML).
  Pins: restic **0.19.1** + resticprofile **0.33.1** (`no_self_update` build),
  sha256-verified in `phase7-backups.sh` — the drill workflow reads the same pin.
- Times (UTC, systemd timers): backup nightly **15:00** · prune Sat 17:00 ·
  `check --read-data-subset=10%` Sun 17:00; retention 7d/4w/6m after each backup.
- Dead-man switch: success-only ping → Uptime Kuma push monitor (Bucket 4) +
  healthchecks.io (off-infra witness). Failure pings on backup/check/prune for
  immediate signal.
- B2: per-box bucket + bucket-scoped key; account region **us-west-004** (US West); 30-day
  file versioning as the delete/overwrite guard (`provisioning/b2/create-backup-bucket.ps1`).
- CI secret names: `RESTIC_PASSWORD` · `RESTIC_B2_KEY_ID` / `RESTIC_B2_KEY` ·
  `HEALTHCHECKS_PING_URL` (single-box v1 — per-box naming graduates with Infisical at box #2).
- Restore drill: monthly `backup-restore-drill` workflow, runner-side (box never
  contacted — total-box-loss path) = the AGENTS.md rule-8 monthly pass; weekly scripted
  CI drill arrives with Stage 2.
- Pre-backup hook pattern: executables in `/etc/resticprofile/pre-backup.d/`
  (dump-before-snapshot; `10-dokploy-postgres-dump` covers the control-plane DB —
  the raw pgdata volume is deliberately not in the set).

## AI gateway (Checkpoint-2 posture)

- Projects stay on **Vercel AI Gateway** (host-independent, zero-markup BYOK) until the
  self-hosted **Bifrost** dogfood service is deployed + drilled (Bucket-5 era) — app-side
  swap is one base-URL env var; that seam goes in every handoff pack.
- Bifrost keys: provider keys (Groq/Gemini) as compose secret-files (→ Infisical at box #2);
  per-project virtual keys with spend caps; agent keys issued the same way (one spend
  choke point for humans + agents).

## Storage geometry (Checkpoint-2)

- Disk demand is portfolio-aggregate (>100 GB combined) → per-workload homes, never one
  giant disk: **R2** = artifacts (zero egress) · **B2** = backups only · per-box block
  storage/HDD volume = reference data (Bucket 6). Analytics: pg_duckdb + Parquet-on-R2
  (Bucket 7).

## Access model

- **CI-as-hands, 443-as-eyes** (outbound 22 blocked from founder network — probed 2026-07-07):
  GHA runners execute box commands over SSH-22; laptop uses Vultr API / Dokploy UI+MCP /
  provider HTTPS console; break-glass = phone hotspot. sshd stays on port 22.
- SSH keypair: `~/.ssh/id_ed25519` (public key on the Vultr account as `swordfish-ops`).

## Secrets model (v1)

- On-box: compose secret-files (+ Dokploy env management for its stacks).
- Laptop: gitignored `.env` holding `VULTR_API_KEY` · `PORKBUN_API_KEY` ·
  `PORKBUN_SECRET_API_KEY` · `B2_APPLICATION_KEY_ID` · `B2_APPLICATION_KEY`.
- Graduation: **Infisical deploys when box #2 goes live** (Stage 3 / Bucket 6).

## Alerts

- ntfy.sh push to founder's phone (random topic; self-host later if earned) +
  UptimeRobot free email as the independent off-infra witness.

## Budget

- Stages 1–2 ceiling: **$30/mo gross**; every spend/resize still gates individually.
- Account facts: Vultr validated with $250 credit; B2 free tier ≥ current needs;
  domain is the only cash spent so far.

## Probe (run anytime)

`scripts/doctor.ps1` — 11 checks: toolchain, 443/22 state, domain DNS, all five key names.
ASCII-only file (PS 5.1 parses it as ANSI — see header comment).
