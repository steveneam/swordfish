#!/usr/bin/env pwsh
# ci-grep-guard.ps1 — anonymity guard.
#
# Fails (exit 1) if any git-TRACKED file references the guarded portfolio
# project token. The token is assembled from fragments at runtime (below) so
# THIS file never contains the literal string and therefore never trips its
# own check — the guard can scan itself and pass, and no path is excluded
# from the grep.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7+. See CI-GUARD.md for rationale.

# Locate the repo root from the SCRIPT's own location, so the guard works no
# matter what the caller's working directory is (CI runs it from repo root; a
# human may invoke it by absolute path from anywhere).
$base = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$root = (& git -C $base rev-parse --show-toplevel 2>$null)
if (-not $root) { Write-Error 'Not inside a git repository.'; exit 2 }

# Assemble the guarded tokens at runtime (never literals on disk).
#
# Unmask history, each a founder call: token C (Thalon = former Project 3)
# 2026-07-08; token A (Eamos = former Project 1) 2026-07-15; token B (Selom =
# former Project 2) 2026-07-17. The portfolio is now FULLY UNMASKED - every
# project may be named in tracked files and no token is guarded.
#
# The list is kept rather than deleted so re-masking a future project stays a
# one-line change and the CI wiring never has to be rebuilt.
#
# An EMPTY list MUST pass, and must not reach git grep: a zero-length regex
# matches EVERY line, so `git grep -E ''` would flag the whole tree and exit 0
# = "hits found" = FAIL. Short-circuit before building the pattern.
$tokens = @()

if ($tokens.Count -eq 0) {
    Write-Host "PASS: no project tokens are currently guarded (portfolio fully unmasked 2026-07-17)."
    exit 0
}
$pattern = ($tokens -join '|')

# Grep TRACKED files only — the correct CI semantics (CI only ever sees committed
# files), and it keeps the gitignored .context/ vault pointer out of scope.
#   -I skip binary   -i case-insensitive   -n line numbers   -E extended regex
$hits = & git -C $root grep -I -i -n -E $pattern
$code = $LASTEXITCODE          # git grep: 0 = matches found, 1 = none, >1 = error

if ($code -eq 0) {
    Write-Host "FAIL: guarded project token(s) found in tracked files:`n"
    $hits | ForEach-Object { Write-Host "  $_" }
    Write-Host "`nMove the offending content out of tracked files (e.g. into gitignored .context/)."
    exit 1
}
elseif ($code -eq 1) {
    Write-Host "PASS: no guarded project tokens in tracked files."
    exit 0
}
else {
    Write-Error "git grep errored (exit code $code)."
    exit $code
}
