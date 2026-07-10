#!/usr/bin/env pwsh
# create-box.ps1 - Bucket 5 (Stage 2): create/verify the syd2 shared box via the
# BinaryLane API. Runbook: CHARTER.md Bucket 5; the provider adapter seam
# (Checkpoint-2 amendment 6). Runs on Windows PowerShell 5.1 and pwsh 7+.
#
# HISTORY NOTE: syd2 itself was first created via the purchase FORM with the
# cloud-init user-data pasted in (the BinaryLane API token only exists
# post-purchase - see syd2-purchase-step-card.md). This script is the scripted
# rebuild path from that point on: its no-op branch is the converge proof
# against the live box, and -Approve can re-create the box from code alone.
#
# SPEND GATE: without -Approve this is a dry run - it resolves and prints exactly
# what would be created (size, region, price, image, key, user-data) and exits.
# Creating a server commits ~AUD $39.20/mo and requires founder approval.
#
# Idempotent: if a server with -Name already exists, prints its row and exits 0.
# No secrets printed; the token comes from env BINARYLANE_API_TOKEN or .env.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [string]$Name = 'syd2.swordfish.cfd',
    [string]$Region = 'syd',
    [string]$Size = 'std-4vcpu',
    [string]$Image = 'ubuntu-24.04',   # 24.04 ONLY - cloud-init pins Docker apt to noble
    [string]$SshKeyName = 'swordfish-ops',
    [string]$CloudInit = (Join-Path $PSScriptRoot '..\cloud-init\syd2.yaml'),
    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- API token: env var, else repo-root .env (gitignored) ---
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

$apiToken = Read-DotEnvValue 'BINARYLANE_API_TOKEN'
if (-not $apiToken) { throw 'BINARYLANE_API_TOKEN not found in environment or .env' }
$headers = @{ Authorization = "Bearer $apiToken" }
$base = 'https://api.binarylane.com.au/v2'

function Invoke-BinaryLane([string]$method, [string]$path, $body) {
    $args = @{ Method = $method; Uri = "$base$path"; Headers = $headers }
    if ($null -ne $body) {
        $args.Body = ($body | ConvertTo-Json -Depth 5)
        $args.ContentType = 'application/json'
    }
    try { return Invoke-RestMethod @args }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw "BinaryLane API $method $path failed: $($_.Exception.Message) $detail"
    }
}

function Get-PublicIp($server) {
    return ($server.networks.v4 | Where-Object { $_.type -eq 'public' } | Select-Object -First 1).ip_address
}

# --- idempotency: existing server with this name is a no-op ---
$existing = (Invoke-BinaryLane GET '/servers?per_page=200' $null).servers | Where-Object { $_.name -eq $Name }
if ($existing) {
    Write-Host "OK (no-op): server '$Name' already exists."
    Write-Host "  id     : $($existing.id)"
    Write-Host "  region : $($existing.region.slug)"
    Write-Host "  size   : $($existing.size.slug)"
    Write-Host "  image  : $($existing.image.slug)"
    Write-Host "  ip     : $(Get-PublicIp $existing)"
    Write-Host "  status : $($existing.status)"
    exit 0
}

# --- resolve size / image / ssh key ---
$sizeInfo = (Invoke-BinaryLane GET '/sizes?per_page=200' $null).sizes | Where-Object { $_.slug -eq $Size }
if (-not $sizeInfo) { throw "Size '$Size' not found in the BinaryLane catalog" }
if ($sizeInfo.regions -and ($sizeInfo.regions -notcontains $Region)) { throw "Size '$Size' not available in region '$Region' right now" }

# per_page is capped at 200 by the BinaryLane API (400 above it - hit live
# 2026-07-10 on the first real create-path run; the syd2-era no-op converge
# exits before this call, so the bug hid until syd4)
$imageInfo = (Invoke-BinaryLane GET '/images?type=distribution&per_page=200' $null).images | Where-Object { $_.slug -eq $Image }
if (-not $imageInfo) { throw "Image '$Image' not found in the BinaryLane catalog" }

$sshKey = (Invoke-BinaryLane GET '/account/keys?per_page=200' $null).ssh_keys | Where-Object { $_.name -eq $SshKeyName }
if (-not $sshKey) { throw "SSH key '$SshKeyName' not found in the BinaryLane account" }

# --- cloud-init user-data (plain string, DO-style; normalize CRLF -> LF) ---
if (-not (Test-Path $CloudInit)) { throw "cloud-init file not found: $CloudInit" }
$userData = (Get-Content $CloudInit -Raw) -replace "`r`n", "`n"
if ($userData -notmatch '^#cloud-config') { throw "user-data does not start with #cloud-config: $CloudInit" }

Write-Host ''
Write-Host 'Would create server:'
Write-Host "  name/hostname : $Name"
Write-Host "  region        : $Region"
Write-Host "  size          : $Size  ($($sizeInfo.vcpus) vCPU / $($sizeInfo.memory) MB / $($sizeInfo.disk) GB) - AUD `$$($sizeInfo.price_monthly)/mo"
Write-Host "  image         : $($imageInfo.slug) ($($imageInfo.name))"
Write-Host "  ssh key       : $($sshKey.name) ($($sshKey.id))"
Write-Host "  user-data     : $CloudInit ($([Text.Encoding]::UTF8.GetByteCount($userData)) bytes)"
Write-Host ''

if (-not $Approve) {
    Write-Host 'DRY RUN - no spend. Re-run with -Approve after the founder approves the purchase (Approval Gate).'
    exit 0
}

$body = @{
    name      = $Name
    region    = $Region
    size      = $Size
    image     = $Image
    ssh_keys  = @($sshKey.id)
    user_data = $userData
    backups   = $false          # off-box restic is the backup story
}
$created = (Invoke-BinaryLane POST '/servers' $body).server
Write-Host "Created server $($created.id) - waiting for it to go active..."

$deadline = (Get-Date).AddMinutes(10)
do {
    Start-Sleep -Seconds 15
    $srv = (Invoke-BinaryLane GET "/servers/$($created.id)" $null).server
    Write-Host "  status=$($srv.status) ip=$(Get-PublicIp $srv)"
} while (($srv.status -ne 'active' -or -not (Get-PublicIp $srv)) -and ((Get-Date) -lt $deadline))

if ($srv.status -ne 'active' -or -not (Get-PublicIp $srv)) {
    throw "Server did not reach active state in time - check the BinaryLane console (id $($created.id))"
}

$ip = Get-PublicIp $srv
Write-Host ''
Write-Host "ACTIVE: $ip  (id $($srv.id))"
Write-Host 'Cloud-init will keep hardening for a few minutes after boot.'
Write-Host "Next: provisioning/porkbun/set-a-record.ps1 -Subdomain syd2 -Ip $ip"
