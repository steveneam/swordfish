# Swordfish

**The portfolio's infrastructure / DevOps ops engine.** Swordfish stands up and operates self-managed VPS infrastructure — DNS · TLS · reverse proxy (Traefik) · containers · auto-deploy · firewall · backups (restic) · monitoring — so an AI agent does the ops and the founder approves. It completes the portfolio's ops trio: **Forj builds · Walter operates · Swordfish hosts/runs.**

**North star:** `swordfish provision <box>` → a hardened, TLS-terminated, container-ready box with off-box backups + uptime monitoring, live in under an hour, from one approved command.

## Layout

| Path | What |
|---|---|
| `provisioning/` | Reproducible box builds — the moat. cloud-init + bash → Ansible + dev-sec → OpenTofu (the ratchet ladder). |
| `compose/` | Traefik + docker-socket-proxy + Dokploy (control plane) + per-workload stack templates. Digest-pinned images. |
| `runbooks/` | provision · deploy · backup-restore · incident · migration. Every runbook command is executed verbatim on the monthly pass. |
| `inventory/` | One row per live box (provider · region · specs · runs-what · $/mo). Secrets never here. |
| `scripts/` | `ci-grep-guard.ps1` (the anonymity guard — required CI check) · `doctor.ps1` (laptop readiness probe). |
| `.github/workflows/` | CI: the guard now; image build+test → GHCR lands with the first containerized workload. |
| `agent_handoff/` | `CURRENT.md` — the session-wrap handoff (one file, overwritten each wrap). |
| `COORDINATION.md` | Parallel-lane board (activates when charter buckets are file-disjoint). |
| `AGENTS.md` ≡ `CLAUDE.md` | The repo operating protocol. Read first. |

## Ground rules (full set in `AGENTS.md`)

- **No local Docker** — images build in CI and run on the VPS; the laptop is git + SSH + browser only.
- **Zero guarded project names in tracked files** — migration targets are Project 1/2/3 only (`scripts/ci-grep-guard.ps1`, required in CI).
- **Backups before workloads; Approval Gate on every spend.**
- **Founder is the sole author** — no AI attribution in commits or PRs.

## Quickstart

```powershell
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1        # laptop readiness
powershell -ExecutionPolicy Bypass -File scripts/ci-grep-guard.ps1 # must PASS before every commit
```

## Status

Bootstrapped 2026-07-07. Next: orient → founder interview → build charter (`CHARTER.md`) → Stage 1 dogfood box (Approval Gate: spend). The stage plan + research live in the founder's research vault (pointer: gitignored `.context/READ-ME-FIRST.md`).
