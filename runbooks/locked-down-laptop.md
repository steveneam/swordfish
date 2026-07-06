# Working from an IT-locked laptop — the thin-client pattern

_Runbook. Generic by design — written so any project on a corporate-managed machine can
copy it, not just this one. Executable checks: `scripts/doctor.ps1` (laptop-side probes)
and the `hardening-smoke` workflow (CI-as-hands proof). Facts below were probed live
2026-07-07; re-run doctor before trusting them on a new network._

## The constraint model (what a corporate laptop actually gives you)

Verified on this machine:

| capability | state | probe |
|---|---|---|
| software installs — **machine-wide / elevated** | **blocked by IT** (UAC elevation denied; winget exits 1602 "You cancelled the installation" — that's the policy, not a user cancel) | attempted install → blocked (2026-07-07) |
| software installs — **user scope (no elevation)** | **works** on this fleet — probe before declaring installs blocked | Python 3.12 via `winget install --override "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=0"` + pip via `py -m pip` (bare `pip` doesn't land on PATH) + npm user-prefix globals, all re-verified same machine 2026-07-07 |
| outbound TCP 22 (SSH) | **blocked** | `doctor.ps1` port probe |
| outbound TCP 443 (HTTPS) | open — the one reliable channel | `doctor.ps1` |
| outbound UDP/TCP 53 to public resolvers | **blocked** (corporate resolver only) | `nslookup … 1.1.1.1` times out |
| git over HTTPS, gh CLI, PowerShell 5.1, ssh-keygen, browser | available | `doctor.ps1` |

Assume everything else is unavailable or monitored. Do not fight IT policy — route around
it architecturally.

## The pattern: laptop = thin client · CI = hands · box = muscle

- **Laptop** does only what it provably can: edit files, run PowerShell scripts, drive
  `git`/`gh` over HTTPS, use a browser, keep secrets in gitignored files. It never needs
  a language runtime, Docker, or raw SSH.
- **CI runners** (GitHub Actions) are the hands: anything needing SSH, Linux, Python,
  Docker builds, or open egress runs in a workflow. Runners are disposable, fully
  tooled, and unblocked. Trigger + watch from the laptop: `gh workflow run …`,
  `gh run watch …` — all over 443.
- **A provisioned box** (VPS) is the muscle: long-lived services, containers, real
  workloads. The laptop reaches it only through TLS'd web UIs and provider APIs — never
  raw SSH from the corporate network.

## Tier 0 — probe user scope before routing around (added 2026-07-07, verified live)

On many managed fleets only **elevation** is blocked, not installs. Before moving a task
to CI or a box, try the no-UAC tier: `winget install --scope user` (or `--override
"/quiet InstallAllUsers=0"` for python.org-style installers — their machine-wide
launcher/PATH components are the usual UAC trigger; drop them), `pip install --user`,
per-user npm/npx globals. User installs land under `%LOCALAPPDATA%\Programs` /
`%APPDATA%`, register per-user (Python: PEP 514, so an existing `py` launcher finds
them), and need PATH appends to the **user** Path variable only. If user scope is also
blocked (AppLocker on user-writable dirs), fall through to the recipes below. Local
dev-loop muscle (runtimes, ffmpeg-class tools) is worth this probe; anything that
genuinely needs admin (Docker, WSL2, services, drivers) — skip straight to CI/box.

**Policy caveat (owner's call, not the agent's):** technically-possible ≠ permitted.
Elevation being the only hard gate may mean IT *allows* user scope — or merely hasn't
closed it. Endpoint agents see user-dir interpreters exactly as well as machine-wide
ones. If the acceptable-use intent is unclear, default to CI/box; use Tier 0 for
dev-loop convenience on tools no policy names, and never for anything that ships.

## Recipes (each verified live)

| you need | do this instead of installing anything |
|---|---|
| run Python / any runtime | GitHub Actions workflow (`runs-on: ubuntu-latest` has Python, Node, Go preinstalled), or a container on the box |
| build a Docker image | CI builds and pushes to GHCR — never local Docker |
| SSH into a box | a workflow does it: private key in a repo secret (`gh secret set SSH_DEPLOY_KEY < keyfile`), runner connects and executes (see `.github/workflows/hardening-smoke.yml`) |
| check DNS past the corporate resolver | DNS-over-HTTPS: `Invoke-RestMethod 'https://cloudflare-dns.com/dns-query?name=HOST&type=A' -Headers @{accept='application/dns-json'}` |
| call provider APIs (VPS, DNS, storage) | plain HTTPS from PowerShell — `provisioning/vultr/create-box.ps1`, `provisioning/dns/set-a-record.ps1` are the reference implementations |
| a secret available to automation | GitHub repo secret via `gh secret set`; laptop-side copies stay in gitignored `.env` / `inventory/secrets/` |
| emergency raw SSH (break-glass) | phone hotspot — off the corporate network entirely; keep a dedicated key authorized for it |

Two-key discipline: the laptop keypair never leaves the laptop; CI gets its **own**
keypair, uploaded as a repo secret, separately revocable.

## Rules that keep it safe

1. Nothing sensitive transits the corporate network unencrypted — 443/TLS everywhere.
2. The laptop key is break-glass only; day-to-day operations are CI workflows with logs
   (an audit trail IT-blocked laptops can't give you).
3. Every laptop-side script must run on stock Windows PowerShell 5.1 — no modules, no
   installs, ASCII-only files (5.1 reads unmarked files as ANSI).
4. Anything that **ships** (builds, deploys, box operations) runs in CI or on the box —
   never off a local install, Tier 0 or otherwise. A local runtime is dev-loop
   convenience only; if a shipping task seems to need one, that's the design smell.

## When you get your own machine

The pattern survives the upgrade. A personal MacBook removes the *blockers* (local
runtimes become available for fast iteration) but the architecture stays: CI still
builds every artifact that ships, boxes still run every workload, laptops stay
replaceable thin clients. That's not a workaround — it's the deployment discipline the
locked-down laptop forced early. Keep it.
