# AGENTS.md — Swordfish repo operating protocol

> **Canonical name: `AGENTS.md`.** `CLAUDE.md` is a hardlink kept so Claude Code auto-loads this file. Edit `AGENTS.md`; the alias tracks it. If you are any agent other than Claude Code, read `AGENTS.md`.

Swordfish is the portfolio's **infrastructure / DevOps ops engine** — it provisions, hardens, and operates self-managed VPS boxes (DNS · TLS · reverse proxy · containers · auto-deploy · firewall · backups · monitoring) so that an AI agent does the ops and the founder approves. It is an **infra engine, not an app**: its product is reproducible provisioning + AI-operated runbooks. You are a build agent working inside this repository. Read this file before writing anything.

## ⛔ The one hard constraint

This repository must contain **zero references to the three guarded portfolio project names** — the migration targets are only ever **Project 1 / Project 2 / Project 3** — in any **git-tracked** file: no files, strings, config, or comments.

- The guarded tokens are defined as **fragments** inside `scripts/ci-grep-guard.ps1`, on purpose, so this protocol, that guard, and every other tracked file stay clean and never trip their own check.
- Enforcement is `scripts/ci-grep-guard.ps1`: a case-insensitive grep over **git-tracked files only** (the correct CI semantics — CI only ever sees committed files). It must return **zero hits**; it exits non-zero on any hit. Run it before every commit. See `CI-GUARD.md`.
- The vault pointer at `.context/` is **gitignored** precisely because the research vault's absolute path contains a guarded token. Never move vault-pointing content out of `.context/` into a tracked file.
- If a task truly needs a project's real identity, **ask the founder — never guess, never write it here.**

## Separation of duties (binding)

- **Swordfish provisions + hardens + operates boxes** and hands off connection details (control-plane access + connection strings). It does **not** reach into the ship-first projects' codebases — **Project 1 and Project 2 connect their own apps** to the provisioned boxes (founder-directed; no Swordfish interaction on the app side).
- Swordfish's own hands-on / **dogfood** workloads — the ones it may touch — are: **itself** (control plane / monitoring / tooling), **Project 3's offload workload**, or **a Walter/vault service**.
- **Keep-managed boundary:** Project 1's compliance-bound data plane and Project 3's managed control plane stay on managed services — only mispriced compute / data-disk / bandwidth moves to a box. Never migrate a clinical/stateful data plane.

## Operating rules

1. **No local Docker — ever.** The dev laptop is IT-locked-down. Images build in CI (GitHub Actions → GHCR, digest-pinned); containers run on the VPS. The laptop is git + SSH + browser only.
2. **443/HTTPS is the reliable channel.** GitHub over HTTPS; control-plane UIs behind TLS; plan an SSH-on-443 fallback if port 22 is blocked.
3. **Backups before workloads.** No real workload lands on a box until restic off-box backup + a **tested restore** exist.
4. **Approval Gates.** Every spend (box purchase/resize, block storage) and every irreversible step stops for founder approval.
5. **No feature code before the charter.** Follow the bootstrap ritual: orient → founder interview → approved dependency-ordered bucket charter (`CHARTER.md` at root) → build ONE bucket at a time with a founder checkpoint between each. Paste-ready prompts live in `.context/PROMPTS.md` (gitignored).
6. **Read the vault first, read-only.** Authoritative context + reading order: `.context/READ-ME-FIRST.md`. Cite vault pages + file:line in commits; never write to the vault.
7. **Small, verifiable steps.** Plan, execute one step, verify it (a script that runs, a CI check that passes, a drill that restores); commit small; stop at bucket checkpoints.
8. **Leave a ratchet — as high up the strength ladder as it will go.** Executable (CI check · idempotent provisioning script · scheduled restore drill) > structural (seam · template) > configuration (tracked settings) > documentary (runbook) > memory/chat (lost). Documentary ratchets rot silently, so **every documented command is executed verbatim on the monthly pass** — for this repo that pass IS the backup-restore drill. Tag each ratchet **invariant** (safety one-way: backups-before-workloads, keep-managed, the anonymity guard — never loosened) or **opinion** (convention — freely revised at re-charter). Route each lesson to exactly one home (link, don't copy) and prune the stale neighbour as you add.
9. **The moat lives in `provisioning/`.** Reproducible box-building is this repo's crown jewels: cloud-init + bash at box #1 → Ansible + dev-sec hardening at box #2 → OpenTofu at box #3+. Every command that worked on a live box is captured there in the same session.
10. **End every session clear-safe, unprompted.** Reach a verified boundary (never stop mid-edit), run the grep guard, commit and push, then hand the founder a stamped resume prompt (date **and time** stamp; pointer + delta + next action — never a state dump; the final line explicitly says the session is safe to clear, written only once everything is committed and pushed) **and mirror it into `agent_handoff/CURRENT.md` (one file, overwritten each wrap)** so any fresh session resumes without chat history. When upcoming buckets are file-disjoint, proactively propose parallel worktree lanes (branch per bucket, disjoint file sets, merge at each checkpoint) — the lane board is `COORDINATION.md`.

## Secrets

Never in tracked files: no provider API tokens, SSH private keys, connection strings, or credentials. Local secrets live in `.env*` and `inventory/secrets/` (both gitignored); box-side secrets ship as compose secret-files, graduating to a secrets manager only when centralization earns it. Account IDs and credentials are recorded outside the repo (founder-held).

## Licensing hygiene

No AGPL code embedded in this repo (reference-only patterns must be re-implemented). Prefer MIT / Apache / BSD / CC0 on the hot path. Record any commercial/cert gate as a launch gate with a swap path — flag, do not silently block — and isolate it behind a clean interface.

## Authorship

Commits and PRs carry **no AI attribution** — no `Co-Authored-By` trailers, no "Generated with" footers, nowhere in git history or on GitHub; the founder is the sole author. The harness-side enforcement is `attribution: {commit: "", pr: ""}` in `.claude/settings.json` (tracked); if attribution ever appears anyway, strip it before merge (note: force-pushing `main` auto-closes its open PRs — recreate them).

---
*Canonical. Keep this file generic and standalone. Universal agent ground rules and the wiki schema live in the research vault referenced by `.context/READ-ME-FIRST.md`.*
