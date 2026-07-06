# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 03:50 +10:00 (Bucket 1.5 close-out + Bucket 2 pre-steps session)_

## State

**Bucket 1.5 COMPLETE** (light checkpoint folded into this session) and **Bucket 2
pre-steps live on syd1** at `8858ad6`. syd1 unchanged in role: live, hardened,
carrying NOTHING until Bucket-3 backups (invariant).

- Renovate: app installed (scoped to `steveneam/swordfish` only), Mend onboarding
  done (**Renovate Only** product — not the license-gated bundle; **Scan and Alert**
  mode — Scan Only would have silenced all PRs). Onboarding PR #1 extended
  (`helpers:pinGitHubActionDigests` + Sydney timezone) and merged (`d5cfb33`).
  New actions now auto-pin to digests; SHA-pin comments stay updated by bot PRs.
- Bucket-2 pre-steps (all four, applied + verified 23/23 assertions green):
  provider firewall `swordfish-syd1` (TCP 22/80/443 v4+v6 only, the layer Docker
  can't bypass) attached to syd1; `daemon.json` log caps (10m×3) + live-restore;
  unattended-upgrades reboot window 18:30 UTC (= pre-dawn Sydney, box stays UTC);
  swap converged (Vultr image ships 6.2G — kept) + swappiness 10.
- New plumbing: `provisioning/vultr/firewall-group.ps1` (idempotent, dry-run
  default, `-Approve` gate); `provisioning/host/phase2-host.sh`;
  `.github/workflows/host-apply.yml` (dispatch-only CI-as-hands apply channel —
  runs converge twice, fails unless run 2 is a no-op, then re-asserts);
  `assert-hardening.sh` 16→23 checks; cloud-init mirrors all of it (rebuild-proof).
- Old question closed: the failed ci-guard run in the founder's screenshot was
  `b91aff7` (guard caught a guarded name in the handoff file); amended to
  `3769cd7` same-session, green ever since. Working as designed.

## Next

1. **Bucket 2 main build:** Traefik v3 + tecnativa/docker-socket-proxy compose
   (proxy on own internal network, `CONTAINERS=1`, `no-new-privileges`,
   security-headers/HSTS + modern-TLS middleware, JSON access logs; publish no
   app ports). Then Dokploy **version-pinned** behind TLS at
   `deploy.swordfish.cfd` (never upgrade Dokploy before `/etc/dokploy` + Traefik
   config are in the restic set — Bucket 3). Extend assertions: no `0.0.0.0`
   published ports besides Traefik 80/443; ssh-audit grade in smoke.
2. **⛔ Gate at the end of 1:** real DNS (`deploy.` A-record via
   `provisioning/dns/set-a-record.ps1`) + first TLS issuance = founder review in
   the browser (green lock) + Dokploy MCP reachable from Claude Code.
3. Renovate PRs will start arriving — review/merge as they come (digest bumps).
4. Vault side (if still pending): research-sync + Bucket-1 blocks into the
   wiki-agent session.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked,
probed) · zero guarded tokens in tracked files — extends to public names (CT
logs, bucket names) · backups before workloads (syd1 carries NOTHING until
Bucket 3) · Projects are 1/2/3 only · every spend is an Approval Gate · founder
is the sole author (no AI attribution).

_All work is committed and pushed — it is safe to clear this session._
