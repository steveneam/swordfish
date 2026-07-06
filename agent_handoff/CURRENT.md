# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 02:10 +10:00_

## State

**Bucket 1 COMPLETE — at its checkpoint awaiting founder review.** The syd1 box is live,
hardened, and CI-verified:

- **Box purchased + provisioned** (founder approved the $12/mo gate this session):
  Vultr `vhf-1c-2gb`, Sydney, Ubuntu 24.04 — **45.63.24.122**, id `729ae60f-d4a1-4087-9920-b84be1a5018e`,
  A-record `syd1.swordfish.cfd` live (Porkbun, TTL 600). $12/mo against the $250 credit,
  within the $30 ceiling. **NO WORKLOADS until Bucket 3 backups exist (invariant).**
- **Hardening proven by CI** (`hardening-smoke` run 28805508029, green): password auth
  refused (publickey-only offer), root refused, and 16/16 on-box assertions — sshd
  (pw off / kbd-interactive off / root off / AllowUsers deploy), ufw active default-deny
  with 22/80/443, fail2ban sshd jail on systemd backend, unattended-upgrades on,
  Docker + compose ready, cloud-init `done`.
- **Everything is code** (`provisioning/`): cloud-init hardens at first boot (both classic
  lockout gates resolved pre-reachability); `create-box.ps1` is idempotent + dry-run by
  default with `-Approve` as the executable spend gate (re-run proven no-op);
  `set-a-record.ps1` idempotent upsert (proven no-op). CI-as-hands works: runner SSHes
  with the dedicated `swordfish-ci` key (repo secret `SSH_DEPLOY_KEY`); founder laptop
  key stays local (break-glass via hotspot).
- **Lesson banked:** PS 5.1 pipe into `gh secret set` newline-mangles key material →
  "error in libcrypto" on the runner. Fixed byte-exact via bash redirect; workflow now
  strips CRs + parse-gates the key (commit 953909e). Transfer secrets via bash, not PS pipes.
- **New runbook:** `runbooks/locked-down-laptop.md` — thin-client/CI-as-hands/box-as-muscle
  pattern for any project on a corporate machine. A second build agent added a verified
  Tier-0 (user-scope installs work on this fleet; elevation is the only hard gate);
  amended with a policy caveat + ships-from-CI-only rule. Executable checks: doctor.ps1
  + hardening-smoke.
- **Guard incident (resolved, lesson binding):** a guarded project name arrived via chat
  and was briefly committed+pushed in this file before the guard result was read — the
  guard ran chained with `;` so its FAIL did not gate the commit. History rewritten
  (amend + force-push) within minutes. New rule: the guard runs ALONE and its exit code
  is checked BEFORE any commit command is issued; agent names from chat are treated as
  guarded until proven otherwise. **Executable ratchet:** `.githooks/pre-commit` now runs
  the guard and blocks the commit itself (`git config core.hooksPath .githooks`, once per
  clone; doctor.ps1 probes the wiring). Residual: the tainted commit is unreachable on
  origin but may persist in provider caches until GC — a support purge is the founder's
  call if that residue matters.

## Next

1. **Founder reviews the Bucket-1 checkpoint** → on go, **Bucket 2** (Stage 1b): Traefik v3
   + tecnativa/docker-socket-proxy (publish no app ports), Dokploy version-pinned behind
   TLS at `deploy.swordfish.cfd`. **Ends at the ⛔ real-DNS + TLS-issuance gate**; verify =
   green-lock UI + Dokploy MCP reachable from Claude Code + RAM headroom recorded.
2. Vault side: founder pastes the Bucket-1 vault-sync block into the wiki-agent session
   (playbook Phases 0–2 executed live; locked-down-laptop runbook created; CI-key lesson).

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked, probed) ·
zero guarded tokens in tracked files — extends to public names (CT logs, bucket names) ·
backups before workloads (syd1 carries NOTHING until Bucket 3) · Projects are 1/2/3 only ·
every spend is an Approval Gate · founder is the sole author (no AI attribution).
