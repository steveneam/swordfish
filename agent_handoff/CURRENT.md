# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 00:04 +10:00_

## State

Repo bootstrapped (by the founder's vault session, from the vault's build plan + bootstrap spec): skeleton dirs (`provisioning/ compose/ runbooks/ inventory/ scripts/ agent_handoff/`), `AGENTS.md` ≡ `CLAUDE.md` protocol, anonymity guard (`scripts/ci-grep-guard.ps1` + CI workflow), `doctor.ps1` readiness probe, lane board, vault pointer + paste-ready prompts staged in gitignored `.context/`. No box exists; no accounts beyond GitHub are assumed.

## Next

1. Founder pastes **Prompt 1 (Orient + Interview)** from `.context/PROMPTS.md` into a fresh Claude Code session opened at this repo root → orientation summary, then a one-question-at-a-time founder interview → dependency-ordered bucket charter at `CHARTER.md`.
2. **No feature code before the charter is approved.**
3. First build slice after charter approval = the Stage-1 dogfood-box provisioning script (Prompt 2). The box purchase itself is an **Approval Gate — do NOT buy a box** until the founder clears it.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel · zero guarded tokens in tracked files (run the guard before every commit) · backups before workloads · migration targets are Project 1/2/3 only · founder is the sole author (no AI attribution).
