# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 03:08 +10:00 (Bucket 1.5 build session)_

## State

**Bucket 1.5 (CI supply-chain hardening) built and CI-verified** at `395289c`, repo-only,
no spend. syd1 unchanged: live, hardened, carrying NOTHING until Bucket-3 backups (invariant).

- Every action SHA-pinned, tag in comment: `actions/checkout` bumped v4 → **v7.0.0**
  (`9c091bb2…`, clears the Node-20 deprecation) in both workflows; `persist-credentials: false`
  on every checkout.
- New `.github/workflows/zizmor.yml`: zizmor-action **v0.5.7** SHA-pinned (`192e21d7…`),
  zizmor binary pinned **1.26.1**, `advanced-security: false` + annotations (private repo,
  no GHAS SARIF) — job fails on any finding. **Green on main.**
- Least-privilege `permissions: contents: read` on all three workflows (stricter than the
  charter's read-all — satisfies the intent); deploy-key job stays dispatch-only.
- `inventory/licensing.md` created (ledger the charter referenced): Renovate AGPL =
  service-use only; zizmor MIT; Dokploy Apache-2.0.
- AGENTS.md rule 10 tightened per founder feedback: resume prompts carry date **and time**
  + an explicit safe-to-clear final line. (Note: editing AGENTS.md breaks the CLAUDE.md
  hardlink — re-create it after any edit; done this session.)
- Verify: zizmor green ✅ · ci-guard green ✅ · zero non-SHA `uses:` refs ✅ (regex-checked) ·
  Renovate onboarding PR ⏳ **founder-gated** (below).

## Next

1. **[founder, ~2 min, browser]** Install the hosted Renovate app: github.com/apps/renovate →
   Install → select **only** `steveneam/swordfish`. The bot then opens the onboarding PR
   (usually < 1 h). Don't pre-commit a renovate config — that suppresses the onboarding PR.
2. **Next session:** review/merge the Renovate onboarding PR (extend its config: keep
   SHA-pin comments updated; docker digest pinning arrives with Bucket 4) → Bucket 1.5
   verify complete → light checkpoint (may merge into the Bucket-2 review).
3. **Bucket 2 on go — pre-steps first:** Vultr firewall group (22/80/443 only, scripted +
   idempotent in `provisioning/vultr/`), Docker `daemon.json` (log caps + live-restore),
   unattended-upgrades reboot window, 1–2 GB swap. Then Traefik v3 + socket-proxy,
   Dokploy version-pinned at `deploy.swordfish.cfd`. Ends at the ⛔ real-DNS + TLS gate.
4. Vault side (if still pending): paste the research-sync block + Bucket-1 block into the
   wiki-agent session.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked, probed) ·
zero guarded tokens in tracked files — extends to public names (CT logs, bucket names) ·
backups before workloads (syd1 carries NOTHING until Bucket 3) · Projects are 1/2/3 only ·
every spend is an Approval Gate · founder is the sole author (no AI attribution).

_All work is committed and pushed — it is safe to clear this session._
