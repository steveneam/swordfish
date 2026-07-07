#!/usr/bin/env pwsh
# set-a-record.ps1 - Bucket 1 (Stage 1a): upsert an A-record on Porkbun (playbook Phase 2).
# Runbook: CHARTER.md Bucket 1. Runs on Windows PowerShell 5.1 and pwsh 7+.
#
# Idempotent upsert: record matches -> no-op; exists with a different IP -> edit;
# missing -> create. Keys come from env vars or the gitignored .env; never printed.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [Parameter(Mandatory = $true)][string]$Ip,
    [string]$Subdomain = 'syd1',
    [string]$Domain = 'swordfish.cfd',
    [string]$Ttl = '600'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

$auth = @{
    apikey       = Read-DotEnvValue 'PORKBUN_API_KEY'
    secretapikey = Read-DotEnvValue 'PORKBUN_SECRET_API_KEY'
}
if (-not $auth.apikey -or -not $auth.secretapikey) { throw 'PORKBUN_API_KEY / PORKBUN_SECRET_API_KEY not found in environment or .env' }

$base = 'https://api.porkbun.com/api/json/v3'

function Invoke-Porkbun([string]$path, $extra) {
    $body = @{}
    $auth.GetEnumerator()  | ForEach-Object { $body[$_.Key] = $_.Value }
    if ($extra) { $extra.GetEnumerator() | ForEach-Object { $body[$_.Key] = $_.Value } }
    $resp = Invoke-RestMethod -Method Post -Uri "$base$path" -Body ($body | ConvertTo-Json) -ContentType 'application/json'
    if ($resp.status -ne 'SUCCESS') { throw "Porkbun API $path returned: $($resp | ConvertTo-Json -Compress)" }
    return $resp
}

$fqdn = "$Subdomain.$Domain"
$existing = (Invoke-Porkbun "/dns/retrieveByNameType/$Domain/A/$Subdomain" $null).records

if ($existing -and $existing[0].content -eq $Ip) {
    Write-Host "OK (no-op): A $fqdn -> $Ip already in place (ttl $($existing[0].ttl))."
    exit 0
}

if ($existing) {
    Invoke-Porkbun "/dns/editByNameType/$Domain/A/$Subdomain" @{ content = $Ip; ttl = $Ttl } | Out-Null
    Write-Host "UPDATED: A $fqdn -> $Ip (was $($existing[0].content))."
} else {
    Invoke-Porkbun "/dns/create/$Domain" @{ name = $Subdomain; type = 'A'; content = $Ip; ttl = $Ttl } | Out-Null
    Write-Host "CREATED: A $fqdn -> $Ip (ttl $Ttl)."
}
Write-Host "Verify propagation: nslookup $fqdn 1.1.1.1"
