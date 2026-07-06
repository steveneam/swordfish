#!/usr/bin/env pwsh
# doctor.ps1 — laptop-side readiness probe (informational; always exits 0).
#
# Checks the locked-down dev laptop can drive Swordfish end-to-end: git + gh
# auth over HTTPS, an ed25519 keypair, 443 reachability, and which Stage-0
# account keys are present. Presence only — no secret values are printed.
# Runs on Windows PowerShell 5.1 and PowerShell 7+.

$results = @()
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $script:results += [pscustomobject]@{
        status = $(if ($ok) { 'PASS' } else { 'WARN' })
        check  = $name
        detail = $detail
    }
}

# --- git ---
$git = Get-Command git -ErrorAction SilentlyContinue
Add-Check 'git' ($null -ne $git) $(if ($git) { (& git --version) } else { 'git not found on PATH' })

# --- gh auth (HTTPS is the reliable channel) ---
$ghOk = $false; $ghDetail = 'gh CLI not found — install GitHub CLI'
if (Get-Command gh -ErrorAction SilentlyContinue) {
    & gh auth status *> $null
    $ghOk = ($LASTEXITCODE -eq 0)
    $ghDetail = if ($ghOk) { 'authenticated' } else { 'run: gh auth login (choose HTTPS)' }
}
Add-Check 'gh auth' $ghOk $ghDetail

# --- SSH keypair ---
$key = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
Add-Check 'ssh keypair (ed25519)' (Test-Path $key) $(if (Test-Path $key) { "$key present" } else { 'run: ssh-keygen -t ed25519' })

# --- 443 reachability (GitHub) ---
$net443 = $false
try { $net443 = Test-NetConnection github.com -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch {}
Add-Check 'github.com:443' $net443 $(if ($net443) { 'reachable' } else { 'blocked? — 443 is the required channel' })

# --- Stage-0 keys: env var or named in a local .env (presence only) ---
$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$envText = if (Test-Path $envFile) { Get-Content $envFile -Raw } else { '' }
$keys = @(
    @{ name = 'VULTR_API_KEY';         why = 'VPS provisioning (Stage 1)' },
    @{ name = 'B2_APPLICATION_KEY_ID'; why = 'backups/artifacts bucket (Stage 1)' },
    @{ name = 'B2_APPLICATION_KEY';    why = 'backups/artifacts bucket (Stage 1)' }
)
foreach ($k in $keys) {
    $present = ([Environment]::GetEnvironmentVariable($k.name)) -or ($envText -match [regex]::Escape($k.name))
    Add-Check $k.name $present $(if ($present) { 'present' } else { "missing — needed for $($k.why)" })
}

$results | Format-Table -AutoSize
$warns = @($results | Where-Object { $_.status -eq 'WARN' }).Count
Write-Host "$($results.Count - $warns)/$($results.Count) checks pass. WARNs are expected until Stage-0 accounts exist."
exit 0
