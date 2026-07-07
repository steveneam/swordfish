# CI Guard — anonymity check

This repository ships a hard invariant: it must contain **zero references to the two guarded portfolio project names** (the anonymized migration targets — written here only as Project 1 / Project 2) in any **git-tracked** file — no files, strings, config, or comments. Swordfish is deliberately project-agnostic; the Project-N ↔ real-name key is held by the founder, outside this repo.

> **Unmask on record (founder call, 2026-07-08):** the former third guarded project — **Project 3 = Thalon** — was unmasked; its guard token (token C) was removed from the script, and Thalon may now be named in tracked files. Tokens A and B remain guarded; everything below applies to them unchanged.

## The check

`scripts/ci-grep-guard.ps1` runs a case-insensitive grep for the two guarded tokens over **git-tracked files only** and:

- prints every offending `path:line`, if any;
- exits **0** when there are zero hits (clean);
- exits **1** when there is at least one hit (fails the build).

Run it locally before every commit, and it runs as a required CI step:

```powershell
pwsh -File scripts/ci-grep-guard.ps1        # PowerShell 7+
# or, Windows PowerShell 5.1:
powershell -ExecutionPolicy Bypass -File scripts/ci-grep-guard.ps1
```

## Why tracked-files-only is correct

CI only ever sees **committed** files, so grepping the tracked set is the true guarantee that the *shipped* repo is clean. It also keeps the repo pristine while the local build agent still has full context:

- The vault pointer lives under `.context/`, which is **gitignored**. The research vault's absolute path itself contains a guarded token, so `.context/` must never be tracked. Because the guard greps only tracked files, `.context/` is correctly out of scope.
- The guarded tokens are **assembled from fragments at runtime** inside `scripts/ci-grep-guard.ps1` (and referred to only obliquely in this document), so the guard, this file, and the rest of the tracked tree never contain the literal strings and therefore never trip their own check. The guard can scan itself and pass — no path is excluded from the grep.

## The rule extends to PUBLIC infrastructure names (invariant)

The grep guard protects tracked *files* — but some strings this repo chooses become **public off-GitHub**, and the anonymity rule follows them there:

- **TLS hostnames are published to Certificate Transparency logs** the moment a certificate is issued. Anyone can enumerate every hostname this project has ever certified.
- **Object-storage bucket names live in a global, probeable namespace.**

So every public-visible name is **neutral by design**: hostnames derive from the engine + region + function only (apex `swordfish.cfd`; boxes `syd1.`; services `deploy.` / `status.` / `metrics.`), and buckets follow `swordfish-<box>-backups`. Never a guarded token, never a guarded project's real name, never anything that maps a guarded workload to its owner. Naming a new public surface? Derive it from *what it does*, not *who it serves*. (Pinned at the founder charter, decision 4/6.)

**Accepted exception (founder call, 2026-07-08):** Thalon is unmasked, and `thalon.org` (+ `www` 301) will point at the shared box's IP alongside the `swordfish.cfd` service hostnames — the reverse-IP / CT-log linkage between those domains is understood and accepted. This acceptance is Thalon-specific; it does not extend to the two guarded projects.

## What this does NOT do

This is the anonymity guard only. It is intentionally **not** a full CI pipeline (no lint/test/build orchestration) — that arrives with the charter-approved build. Adding this one guard now keeps the invariant enforceable from commit one.
