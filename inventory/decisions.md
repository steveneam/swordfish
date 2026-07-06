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
- Docker `daemon.json`: json-file log caps (`max-size`/`max-file`) + `live-restore: true`.
- unattended-upgrades reboot window (kernel updates need reboots; no Ubuntu Pro attach).
- Published-ports rule is executable: CI asserts no `0.0.0.0` publishes besides Traefik 80/443.
- GitHub Actions: SHA-pinned only; zizmor lints workflows; Renovate maintains pins.
- Dokploy: version-pinned; never upgrade before its config is in the backup set.

## Backup parameters (Bucket 3 implements)

- restic → B2, nightly, encrypted; driven by **resticprofile** (tracked YAML).
- Retention: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`; weekly
  `restic check --read-data-subset=10%`.
- Dead-man switch: success-only ping → Uptime Kuma push monitor + healthchecks.io
  (off-infra witness).
- B2: per-box bucket + bucket-scoped key; account region **us-west-004** (US West); ~30-day
  file versioning as the delete/overwrite guard.
- Restore drill: monthly (= the AGENTS.md rule-8 monthly pass); weekly scripted CI drill
  arrives with Stage 2.

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
