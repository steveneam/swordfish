# Backup + restore (Bucket 3)

Nightly restic → B2, encrypted, config-as-code. The strong ratchets are executable:
`backups-apply` (converge + first backup + posture re-assert) and
`backup-restore-drill` (**THE monthly pass** — AGENTS.md rule 8). This page holds
what a human needs around them.

## What is backed up, where, when

- **Repository:** `b2:swordfish-syd1-backups:restic` (B2 US West, private bucket,
  deleted/overwritten file versions kept 30 days — `provisioning/b2/create-backup-bucket.ps1`).
- **Set** (allow-list in `provisioning/backup/profiles.yaml`): `/etc/dokploy`
  (control plane + Traefik dynamic + acme.json) · `/opt/swordfish` (edge compose +
  backup layer as-deployed) · `/var/backups/swordfish` (pre-backup dumps) ·
  dokploy's `/root/.docker` volume. The raw `dokploy-postgres` volume is
  **deliberately absent** — the pre-backup `pg_dump` hook is what restores
  (dump-before-snapshot; the pattern for every future stateful workload:
  drop an executable in `provisioning/backup/pre-backup.d/`, no extension).
  Bucket 4 added `20-dogfood-sqlite-dumps`: host-side `sqlite3 .backup` of the
  Uptime Kuma db (monitors, push token, ntfy config) + Beszel hub PocketBase
  dbs into `/var/backups/swordfish/` — raw kuma/beszel volumes likewise absent.
- **Schedule** (UTC; systemd timers on the box): backup nightly 15:00 ·
  prune Sat 17:00 · `check --read-data-subset=10%` Sun 17:00.
  Retention 7 daily / 4 weekly / 6 monthly, applied after each backup.

## Secrets map (no values here — locations only)

| what | box (0600 root) | CI (repo secret) | founder-held |
|---|---|---|---|
| repo password | `/etc/resticprofile/password.txt` | `RESTIC_PASSWORD` | `inventory/secrets/restic-syd1.password` + password manager |
| bucket-scoped B2 key | `/etc/resticprofile/b2.env` | `RESTIC_B2_KEY_ID` / `RESTIC_B2_KEY` | `inventory/secrets/b2-syd1-restic.env` + password manager |
| dead-man ping URL | `/etc/resticprofile/hc-url` | `HEALTHCHECKS_PING_URL` | healthchecks.io account |
| kuma push URL | `/etc/resticprofile/kuma-url` | `KUMA_PUSH_URL` | `inventory/secrets/kuma-push-url.txt` (regenerable in Kuma UI) |
| kuma admin login | — | — | `inventory/secrets/kuma-admin.password` (user `swordfish`) + password manager |
| beszel admin login | — | — | `inventory/secrets/beszel-admin.password` (user `ops@swordfish.cfd`) + password manager |

**The repo password + B2 key are the whole DR story** — with them, restore needs
nothing from the box or laptop. Losing the password = losing every backup; it must
exist in the password manager, not only in CI.

## The monthly pass (= the restore drill)

```
gh workflow run backup-restore-drill.yml
```

Green means: repo integrity checked, latest snapshot restored **onto the runner**
(the box is never contacted — total-box-loss path), content verified (real pg_dump,
edge config matches the repo), RTO/RPO measured in the job summary. Record each
run below. A `cmp` failure = backup staleness or unconverged box drift — chase it,
don't re-run until green.

Cockpit twin (syd3, no Docker/edge): `gh workflow run cockpit-restore-drill.yml` —
SYD3_-scoped secrets, fresh-box baseline content checks (grow them as the cockpit
gains state; see the workflow's verify step).

| date (UTC) | snapshot | RTO (restore) | RPO (snapshot age) | notes |
|---|---|---|---|---|
| 2026-07-07 | `f810278c` | 3 s (12 files, 192K) | 0 h (drill ran minutes after first backup; steady-state worst case ~24 h) | first drill — run 28854625726; `restic check` clean; pg_dump + repo cross-check green |
| 2026-07-10 | `1f917946` | 3 s (5 files, 48K) | 0 h (minutes after first backup) | **syd3 cockpit** — cockpit-restore-drill run 29092092325; `restic check` clean; fresh-box baseline verified (fleet keypair in restored authorized_keys). Lesson on record in profiles.yaml: resticprofile `inherit` merges lists positionally — standalone profile for structurally-different boxes. syd3 off-infra dead-man leg went live later the same day (receiver-acked, apply run 29092668496) |
| 2026-07-10 | `52992f70` | 3 s (8 files, 80K) | 0 h (minutes after first backup) | **syd4 workspace** — cockpit-restore-drill run 29094932952 (`secret_prefix=SYD4` — first use of the generalized per-box workflows); `restic check` clean; fresh-box baseline verified; dead-man off-infra leg receiver-acked on apply run 29094751183. Grow content checks after the portfolio restore lands |

## Dead-man's switch

`hc-ping.sh success` fires after every nightly backup → **two independent
receivers**: healthchecks.io (off-infra witness: alerts when the ping goes
**missing**, even if the box died) and, since Bucket 4, the Uptime Kuma push
monitor `swordfish-syd1-backup` (on-infra half → ntfy phone push); `fail`
pings fire on backup/check/prune failure for immediate signal.

- Check settings: period **1 day**, grace **6 h** (backup 15:00 UTC → alert by
  ~21:00 UTC / 07:00 AEST worst case).
- Test-fire: dispatch `backups-apply` with `test_deadman: true` (pings `/fail`,
  then success to clear) and confirm the notification arrived.

## Restore paths

- **Single file / dir, box alive:**
  `sudo resticprofile -c /etc/resticprofile/profiles.yaml --name syd1 restore latest --target /tmp/restore --include <path>` — then copy into place.
- **Control-plane DB:** restore `/var/backups/swordfish/dokploy-postgres.sql.gz`,
  then `zcat ... | docker exec -i <dokploy-postgres-ctr> psql -U dokploy -d dokploy`
  (stop the dokploy service first, restart after).
- **Total box loss:** rebuild = `cloud-init` → `host-apply` → `edge-apply` →
  `backups-apply` (same repo password/key = same repository) → restore
  `/etc/dokploy` + DB dump over the fresh converge → `hardening-smoke`.
  Everything needed is CI secrets + this repo.

## Upgrades / pins

restic + resticprofile versions and sha256 pins live in
`provisioning/host/phase7-backups.sh` (the drill workflow reads the same pin —
one source of truth); resticprofile is the `no_self_update` build on purpose.
Bump = edit pins → `backups-apply` → drill. **Dokploy upgrades are unblocked as
of Bucket 3** (its config + DB dump are in the set) — protocol in `runbooks/edge.md`.

## Watch-items

- The bucket-scoped key can hard-delete file versions (`deleteFiles` — restic
  needs it for prune/unlock); the 30-day version retention is the compromise on
  record (CHARTER pinned decision 6). A split append-only/prune key pair is the
  documented tightening if the threat model grows teeth.
- Weekly scripted CI restore drill (beyond this monthly pass) = named Stage-2
  upgrade (opinion ratchet, CHARTER pinned decision 5).
