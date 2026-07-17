# CI Guard — anonymity check

This repository ships a hard invariant: it must contain **zero references to any guarded portfolio project name** in any **git-tracked** file — no files, strings, config, or comments.

> ## ⚠️ Status 2026-07-17: the portfolio is FULLY UNMASKED — the guarded set is EMPTY.
>
> Three founder calls retired the three tokens in turn: **Project 3 = Thalon** (2026-07-08, token C) · **Project 1 = Eamos** (2026-07-15, token A) · **Project 2 = Selom** (2026-07-17, token B). All three may now be named freely in tracked files.
>
> **The guard is kept, not deleted** — with an empty token list it short-circuits to PASS. Re-masking a future project is a one-line change (`$tokens = @('fr' + 'agment')`) and the CI wiring never has to be rebuilt. Everything below describes the machinery as it behaves the moment a token is added back.
>
> **The empty-list trap, handled:** a zero-length regex matches *every* line, so `git grep -E ''` would report the whole tree as hits and exit 0 = "hits found" = FAIL. The script therefore returns before building a pattern when the list is empty. Both directions are proven: empty → PASS(0); re-armed with a token known to be present → FAIL(1) listing hits.

## The check

`scripts/ci-grep-guard.ps1` runs a case-insensitive grep for the guarded tokens over **git-tracked files only** and:

- prints every offending `path:line`, if any;
- exits **0** when there are zero hits (clean);
- exits **1** when there is at least one hit (fails the build).

Run it locally before every commit, and it runs as a required CI step:

```powershell
pwsh -File scripts/ci-grep-guard.ps1        # PowerShell 7+
# or, Windows PowerShell 5.1:
powershell -ExecutionPolicy Bypass -File scripts/ci-grep-guard.ps1
```

## Two lines of defence: the hook PREVENTS, CI DETECTS

`scripts/hooks/pre-commit` (enabled with `git config core.hooksPath scripts/hooks`)
runs the guard and **refuses to create the commit** if it fails. `ci-guard.yml`
remains the required status check on the remote. Both, not either — CI catches a
machine whose hook isn't wired; the hook stops the bad object ever existing.

**A fresh clone does not inherit `core.hooksPath`** — re-run that one `git config`
line after cloning (CI still covers you until you do).

### Incident that bought this hook (2026-07-13)

The guard was being invoked as `pwsh scripts/ci-grep-guard.ps1 | tail -1 && git commit …`.
**A pipeline's exit status is its LAST command's** — `tail` exited 0, so the `&&`
fired even though the guard had *failed*, and a guarded project name was committed
and pushed to `main`. Remediation needed a history rewrite plus a temporary
relaxation of branch protection (force-pushes are otherwise disabled). The lesson
generalizes past this repo: **never pipe a verification command into `tail`/`head`/
`grep` inside an `&&` chain** — capture its exit code directly, which is precisely
what the hook now does on every commit, whether or not anyone remembers to.

## Why tracked-files-only is correct

CI only ever sees **committed** files, so grepping the tracked set is the true guarantee that the *shipped* repo is clean. It also keeps the repo pristine while the local build agent still has full context:

- The vault pointer lives under `.context/`, which is **gitignored**. Its absolute path contained a guarded token; that token is now retired, but `.context/` stays gitignored — it is the vault pointer, and untracking it was never about the token alone.
- Guarded tokens are **assembled from fragments at runtime** inside `scripts/ci-grep-guard.ps1`, so the guard never contains the literal strings and never trips its own check. It can scan itself and pass — no path is excluded from the grep. (With the set empty this is moot; it matters again the moment a token returns.)

## The rule extends to PUBLIC infrastructure names (invariant)

The grep guard protects tracked *files* — but some strings this repo chooses become **public off-GitHub**, and the anonymity rule follows them there:

- **TLS hostnames are published to Certificate Transparency logs** the moment a certificate is issued. Anyone can enumerate every hostname this project has ever certified.
- **Object-storage bucket names live in a global, probeable namespace.**

So every public-visible name is **neutral by design**: hostnames derive from the engine + region + function only (apex `swordfish.cfd`; boxes `syd1.`; services `deploy.` / `status.` / `metrics.`), and buckets follow `swordfish-<box>-backups`. Never a guarded token, never a guarded project's real name, never anything that maps a guarded workload to its owner. Naming a new public surface? Derive it from *what it does*, not *who it serves*. (Pinned at the founder charter, decision 4/6.)

**Accepted exception (founder call, 2026-07-08):** Thalon is unmasked, and `thalon.org` (+ `www` 301) will point at the shared box's IP alongside the `swordfish.cfd` service hostnames — the reverse-IP / CT-log linkage between those domains is understood and accepted.

**Still the default after the 2026-07-17 full unmask.** Unmasking removed the *grep* constraint; it did not make owner-mapped public naming a good idea. Public surfaces stay derived from **what they do, not who they serve** — that is a design convention worth keeping on its own merits (it keeps hostnames stable when a tenant is renamed, sold, or retired), and it is the cheap default. Name a public surface after a project only as a deliberate, recorded call, the way `thalon.org` was.

## What this does NOT do

This is the anonymity guard only. It is intentionally **not** a full CI pipeline (no lint/test/build orchestration) — that arrives with the charter-approved build. Adding this one guard now keeps the invariant enforceable from commit one.
