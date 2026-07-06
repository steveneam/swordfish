#!/usr/bin/env pwsh
# create-box.ps1 - Bucket 1 (Stage 1a): create the syd1 dogfood box via the Vultr API.
# Runbook: CHARTER.md Bucket 1; playbook Phase 0. Runs on Windows PowerShell 5.1 and pwsh 7+.
#
# SPEND GATE: without -Approve this is a dry run - it resolves and prints exactly
# what would be created (plan, region, price, OS, key, user-data) and exits.
# Creating the instance commits ~$12/mo and requires the founder-approved -Approve.
#
# Idempotent: if an instance with -Label already exists, prints its row and exits 0.
# No secrets printed; the API key comes from env VULTR_API_KEY or the gitignored .env.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [string]$Label = 'syd1',
    [string]$Region = 'syd',
    [string]$Plan = 'vhf-1c-2gb',
    [string]$OsName = 'Ubuntu 24.04 LTS x64',
    [string]$SshKeyName = 'swordfish-ops',
    [string]$CloudInit = (Join-Path $PSScriptRoot '..\cloud-init\syd1.yaml'),
    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- API key: env var, else repo-root .env (gitignored) ---
function Read-DotEnvValue([string]$name) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
    $envFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.env'
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            if ($line -match ('^\s*' + [regex]::Escape($name) + '\s*=\s*(.+)$')) { return $Matches[1].Trim() }
        }
    }
    return $null
}

$apiKey = Read-DotEnvValue 'VULTR_API_KEY'
if (-not $apiKey) { throw 'VULTR_API_KEY not found in environment or .env' }
$headers = @{ Authorization = "Bearer $apiKey" }
$base = 'https://api.vultr.com/v2'

function Invoke-Vultr([string]$method, [string]$path, $body) {
    $args = @{ Method = $method; Uri = "$base$path"; Headers = $headers }
    if ($null -ne $body) {
        $args.Body = ($body | ConvertTo-Json -Depth 5)
        $args.ContentType = 'application/json'
    }
    try { return Invoke-RestMethod @args }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw "Vultr API $method $path failed: $($_.Exception.Message) $detail"
    }
}

# --- idempotency: existing instance with this label is a no-op ---
$existing = (Invoke-Vultr GET '/instances?per_page=500' $null).instances | Where-Object { $_.label -eq $Label }
if ($existing) {
    Write-Host "OK (no-op): instance '$Label' already exists."
    $existing | Select-Object id, label, region, plan, main_ip, status, power_status, server_status | Format-List
    exit 0
}

# --- resolve os / plan / ssh key ---
$os = (Invoke-Vultr GET '/os?per_page=500' $null).os | Where-Object { $_.name -eq $OsName }
if (-not $os) { throw "OS '$OsName' not found in Vultr catalog" }

$planInfo = (Invoke-Vultr GET '/plans?type=vhf&per_page=500' $null).plans | Where-Object { $_.id -eq $Plan }
if (-not $planInfo) { throw "Plan '$Plan' not found" }
if ($planInfo.locations -notcontains $Region) { throw "Plan '$Plan' not available in region '$Region' right now" }

$sshKey = (Invoke-Vultr GET '/ssh-keys?per_page=500' $null).ssh_keys | Where-Object { $_.name -eq $SshKeyName }
if (-not $sshKey) { throw "SSH key '$SshKeyName' not found in the Vultr account" }

# --- cloud-init user-data (normalize CRLF -> LF before encoding) ---
if (-not (Test-Path $CloudInit)) { throw "cloud-init file not found: $CloudInit" }
$yaml = (Get-Content $CloudInit -Raw) -replace "`r`n", "`n"
$userData = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($yaml))

Write-Host ''
Write-Host "Would create instance:"
Write-Host "  label/hostname : $Label  (syd1.swordfish.cfd once the A-record lands)"
Write-Host "  region         : $Region"
Write-Host "  plan           : $Plan  ($($planInfo.vcpu_count) vCPU / $($planInfo.ram) MB / $($planInfo.disk) GB NVMe) - `$$($planInfo.monthly_cost)/mo"
Write-Host "  os             : $($os.name) (id $($os.id))"
Write-Host "  ssh key        : $($sshKey.name) ($($sshKey.id))"
Write-Host "  user-data      : $CloudInit ($([Text.Encoding]::UTF8.GetByteCount($yaml)) bytes)"
Write-Host ''

if (-not $Approve) {
    Write-Host 'DRY RUN - no spend. Re-run with -Approve after the founder approves the purchase (Approval Gate).'
    exit 0
}

$body = @{
    region           = $Region
    plan             = $Plan
    os_id            = $os.id
    label            = $Label
    hostname         = $Label
    sshkey_id        = @($sshKey.id)
    user_data        = $userData
    backups          = 'disabled'   # off-box restic is the backup story (Bucket 3)
    activation_email = $false
    tags             = @('swordfish')
}
$created = (Invoke-Vultr POST '/instances' $body).instance
Write-Host "Created instance $($created.id) - waiting for it to go active..."

$deadline = (Get-Date).AddMinutes(8)
do {
    Start-Sleep -Seconds 10
    $inst = (Invoke-Vultr GET "/instances/$($created.id)" $null).instance
    Write-Host "  status=$($inst.status) power=$($inst.power_status) ip=$($inst.main_ip)"
} while ((($inst.status -ne 'active') -or ($inst.main_ip -eq '0.0.0.0')) -and ((Get-Date) -lt $deadline))

if ($inst.status -ne 'active' -or $inst.main_ip -eq '0.0.0.0') {
    throw "Instance did not reach active state in time - check my.vultr.com (id $($created.id))"
}

Write-Host ''
Write-Host "ACTIVE: $($inst.main_ip)  (id $($inst.id))"
Write-Host 'Cloud-init will keep hardening for a few minutes after boot.'
Write-Host 'Next: provisioning/dns/set-a-record.ps1 -Ip ' -NoNewline; Write-Host $inst.main_ip
