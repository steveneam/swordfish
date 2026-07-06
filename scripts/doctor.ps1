#!/usr/bin/env pwsh
# doctor.ps1 - laptop-side readiness probe (informational; always exits 0).
#
# Checks the locked-down dev laptop can drive Swordfish end-to-end: git + gh
# auth over HTTPS, an ed25519 keypair, 443 reachability, outbound-22 state,
# domain resolution, and which Stage-0 account keys are present. Presence
# only - no secret values are printed.
# Runs on Windows PowerShell 5.1 and PowerShell 7+.
#
# KEEP THIS FILE ASCII-ONLY. PS 5.1 reads unmarked files as ANSI; a UTF-8
# em-dash once decoded into a smart quote and broke the parser (Bucket 0).

$results = @()
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $script:results += [pscustomobject]@{
        status = $(if ($ok) { 'PASS' } else { 'WARN' })
        check  = $name
        detail = $detail
    }
}

# fast TCP probe (3s timeout; Test-NetConnection waits ~20s on filtered ports)
function Test-Port([string]$hostName, [int]$port, [int]$timeoutMs = 3000) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($hostName, $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs) -and $tcp.Connected
    } catch { $ok = $false }
    finally { $tcp.Close() }
    return $ok
}

# --- git ---
$git = Get-Command git -ErrorAction SilentlyContinue
Add-Check 'git' ($null -ne $git) $(if ($git) { (& git --version) } else { 'git not found on PATH' })

# --- gh auth (HTTPS is the reliable channel) ---
$ghOk = $false; $ghDetail = 'gh CLI not found - install GitHub CLI'
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
$net443 = Test-Port 'github.com' 443
Add-Check 'github.com:443' $net443 $(if ($net443) { 'reachable' } else { 'blocked? - 443 is the required channel' })

# --- outbound 22 (informational - blocked is EXPECTED on the corporate network) ---
$net22 = Test-Port 'github.com' 22
Add-Check 'outbound ssh-22 (info)' $true $(if ($net22) { 'open from this network' } else { 'blocked - expected; CI-as-hands model covers it (CHARTER.md decision 2)' })

# --- infra domain resolution (informational - propagation state) ---
$domain = 'swordfish.cfd'
$dnsDetail = 'not resolving yet (propagation, or corporate resolver lag)'
try {
    $addrs = [System.Net.Dns]::GetHostAddresses($domain)
    if ($addrs.Count -gt 0) { $dnsDetail = "resolves ($($addrs[0].IPAddressToString))" }
} catch {}
Add-Check "$domain DNS (info)" $true $dnsDetail

# --- Stage-0 keys: non-empty env var or non-empty value in local .env ---
$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$envText = if (Test-Path $envFile) { Get-Content $envFile -Raw } else { '' }
$keys = @(
    @{ name = 'VULTR_API_KEY';           why = 'VPS provisioning (Bucket 1)' },
    @{ name = 'PORKBUN_API_KEY';         why = 'DNS records (Bucket 1)' },
    @{ name = 'PORKBUN_SECRET_API_KEY';  why = 'DNS records (Bucket 1)' },
    @{ name = 'B2_APPLICATION_KEY_ID';   why = 'backups bucket (Bucket 3)' },
    @{ name = 'B2_APPLICATION_KEY';      why = 'backups bucket (Bucket 3)' }
)
foreach ($k in $keys) {
    $envVal = [Environment]::GetEnvironmentVariable($k.name)
    $inEnvVar  = -not [string]::IsNullOrWhiteSpace($envVal)
    $inEnvFile = $envText -match ('(?m)^\s*' + [regex]::Escape($k.name) + '=\s*\S')
    $present = $inEnvVar -or $inEnvFile
    Add-Check $k.name $present $(if ($present) { 'present' } else { "missing - needed for $($k.why)" })
}

$results | Format-Table -AutoSize
$warns = @($results | Where-Object { $_.status -eq 'WARN' }).Count
Write-Host "$($results.Count - $warns)/$($results.Count) checks pass. A WARN = a missing prerequisite; see CHARTER.md Bucket 0."
exit 0
