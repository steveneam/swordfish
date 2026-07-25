# Nango integration runbook — wiring a portfolio project onto a swordfish broker

**Ownership (founder call 2026-07-25): swordfish owns Nango as a portfolio
capability** — the broker fleet (instances, security, backups, upgrades) AND
the integration wiring process, well enough to walk any project through it.
The app-side code stays the project's (separation of duties unchanged);
swordfish supplies the instance, the keys, and this recipe. Selom is the
worked example — every step below was proven live 2026-07-23→25.

## 0 · Mint the instance (swordfish)

Per-project instance, never a shared account (see README, multi-project
pattern). Clone this directory, change `PROJECT`/`SERVICE`/`HOSTNAME_PUB`,
mint a fresh secrets file (fresh `NANGO_ENCRYPTION_KEY` — **never rotates,
ever**; it encrypts OAuth tokens at rest), run `provision.sh`. Before any
real connection lands: a sibling of `40-nango-postgres-dump` + a restore
drill (backups-before-workloads).

## 1 · Hand the project its secret key (swordfish)

The `:hosted` image is **email-session auth** — a headless API signin with
`NANGO_DASHBOARD_USERNAME` fails (400 "invalid email"), so the reliable path
is the DB: the per-environment secret keys sit **plaintext by Nango's design**
in `nango._nango_environments` (account 0; `dev` + `prod` rows, `secret_key`
column). Read it on-box (dokploy-gated instance → `docker exec <nango-db>
psql`), drop it in `~/.config/agent-env/<project>-nango.creds` (0600,
deploy-local, never in a repo) with `<PROJECT>_NANGO_SECRET_KEY=…` +
`<PROJECT>_NANGO_BASE_URL=https://<host>`. Values never in chat/prose.

**Wrong-instance tell (selom's preflight lesson):** a secret key used against
an instance it doesn't belong to returns `unknown_account` — one command
distinguishes prod from any dev copy. Never diagnose the prod broker against
a workspace-box copy.

## 2 · Provider app + callback (project + founder)

- The **project** creates/holds the provider OAuth app (Google Cloud client,
  Dropbox app, …). Provider client id/secret live in the PROJECT's gitignored
  env — **they never pass through swordfish's hands.**
- The **founder** pastes the callback into the provider console:
  `https://<host>/oauth/callback` (pre-stage the exact string; his step is
  paste-only). Same URL prints in the server boot banner — that's the confirm.
- Scope hygiene: prefer non-sensitive scopes (`drive.file` avoided Google's
  CASA review entirely — selom 07-25).

## 3 · Create integrations (project, with its secret key)

`POST /config` (Bearer = secret key) with provider, unique key, and the
provider credentials — done by the project so step 2's boundary holds.
Worked examples: `google-drive` (scope `drive.file`) and `dropbox`
(`files.content.write files.content.read files.metadata.read
account_info.read`). Verify: `GET /integrations` 200 lists them.

## 4 · Connect an end user (project drives, founder consents)

Two flows:
- **Direct link (works today, no extra infra):** mint a connect session
  token server-side, send the founder/user
  `https://<host>/oauth/connect/<integration>?connect_session_token=…`,
  they consent in-browser.
- **Embedded ConnectUI widget (`@nangohq/frontend`):** needs a public origin
  for the Connect UI (`:3009` internal) — a second compose domain, e.g.
  `connect.<host>` (queued for selom, founder-gated; may require flipping
  `NANGO_PUBLIC_CONNECT_URL` to the new host — check Nango docs, it's a
  compose-env change + redeploy).

## 5 · Verify end-to-end (the selom-proven sequence)

① connection exists with the granted scope only ② refresh token present and
a **forced refresh succeeds** ③ a live proxy probe returns real data
(`GET /proxy/drive/v3/about` → 200 with the account) ④ the broker's public
gates hold: `/health` 200, `/connection` **401** without auth. All four, not
the first two — corroborate before reporting.

## 6 · Owner's standing duties (swordfish)

- **Backups:** per-instance dump hook + restore drill; the dump is useless
  without that instance's `NANGO_ENCRYPTION_KEY` (three-artifact restore —
  see README).
- **Version policy:** compose currently rides the floating `:hosted` tag
  (0.71.2 live 07-25) — pin at the next quiet window and bump deliberately
  thereafter (queued).
- **Security posture:** server API + dashboard 401-gated; only `/health`,
  `/oauth/callback`, SPA shell public. Re-verify after any compose change.
- **What swordfish never holds:** provider client secrets (project's), the
  founder's provider-console logins. What it always holds: the instance,
  its encryption key, its backups, this runbook.
