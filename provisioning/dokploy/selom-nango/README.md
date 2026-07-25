# selom-nango — self-hosted Nango OAuth broker (syd2)

Selom's OAuth broker for cloud-storage integrations (google-drive, dropbox →
the founder's ERG files). Owner-approved 2026-07-23; stood up live the same
day. **Public at `https://nango.swordfish.cfd`** — swordfish.cfd by founder
call so `selom.app` stays 100% dark (zero CT entries) pre-launch. Callback URL
integrations use: `https://nango.swordfish.cfd/oauth/callback`.

- `compose.yml` — the raw compose, verbatim source of truth (Dokploy holds a
  copy as `sourceType: raw`; edit HERE, converge with `provision.sh`).
- `provision.sh` — idempotent converge: project → compose → env → deploy →
  domain → outside-in verify. Safe to re-run any time; prints OK/CHANGED.

Live identity (2026-07-23): Dokploy project `selom` `8HRcnaTx0iHA56I2AJCHp`,
compose `nango` `mFzE2Wuw_fr0hoi3DMjv_` (env `TDDl5S5VwTunpQGeoaBR8`), appName
`selom-nango-qmolev`. IDs are informational — the script resolves by NAME so a
rebuild mints fresh ones.

## Secrets (never in git)

`inventory/secrets/dokploy-tenant-selom-nango.env` (0600) holds every injected
value; `provision.sh` pushes exactly the keys `compose.yml` interpolates. The
prod env **secret key** (selom's API credential) lives in the Nango DB
(`nango._nango_environments`, plaintext by Nango's design) and was handed to
selom via `~/.config/agent-env/selom-nango.creds` (0600).

## ⚠ Restore story — three artifacts, all required

**`NANGO_ENCRYPTION_KEY` must NEVER rotate.** It encrypts stored OAuth tokens
at rest; the DB dump decrypts to nothing without exactly this key.

1. **Stack:** `provision.sh` (uses `compose.yml` + the secrets file).
2. **Data:** restore `nango-postgres.sql.gz` from the restic snapshot — dumped
   nightly by `provisioning/backup/pre-backup.d/40-nango-postgres-dump`
   (Dokploy-gated: only arms on the box running the production control plane).
   Restore-drill proven 2026-07-23 (0 errors; envs 2, configs 2).
3. **Key:** the same `NANGO_ENCRYPTION_KEY` from the secrets file (also
   founder-held off-box). Stack + data + key → connections survive; any two
   without the third → broker works but every OAuth grant must be redone.

## Multi-project pattern (founder Q 2026-07-25)

Other projects wanting Nango get their **own instance, not a share of this
one**. The `:hosted` community image is single-account — sharing would put
every project's OAuth connections in selom's account, readable with selom's
secret key (a cross-tenant boundary break). Clone instead: copy this
directory, change PROJECT/SERVICE/HOSTNAME_PUB + mint a fresh secrets file
(fresh `NANGO_ENCRYPTION_KEY` — per-instance, each one never-rotate), run
`provision.sh`. Ports never conflict: 3003/3009 are internal to each stack's
own network; the public face is a distinct hostname behind 443. Each instance
idles ~300-400 MB (server capped 1G) — syd2 carries 2-3 comfortably, more
feeds the standing resize gate. Each new instance also needs a sibling of
`40-nango-postgres-dump` (or that hook generalized) BEFORE real connections
land: backups-before-workloads.

## Boundaries

Swordfish owns box + edge + this broker's uptime/backups. **Selom owns the app
side** — integrations, connect flows, consuming the API with its secret key.
Server API (`/connection`) and dashboard API (`/api/v1/*`) are 401-gated; only
`/health`, `/oauth/callback`, and the SPA shell are public (verified
2026-07-23). Dashboard login is email+password (`:hosted` image) — username
`selom-admin` baked in compose, password in the secrets file.
