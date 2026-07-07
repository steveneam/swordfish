#!/usr/bin/env pwsh
# set-firewall.ps1 - Bucket 5: provider-side firewall for syd2 allowing TCP
# 22/80/443 only (BinaryLane "advanced firewall"; mirror of
# provisioning/vultr/firewall-group.ps1 on the old provider).
# Runbook: CHARTER.md Bucket 5 / Bucket-2 pre-step pattern. PS 5.1 + pwsh 7+.
#
# Why a provider firewall when ufw already exists: Docker publishes ports via
# iptables ahead of ufw's chains, so a container port can be reachable even when
# ufw never allowed it. The provider firewall sits outside the OS - Docker cannot
# bypass it. Rules mirror ufw (22/80/443) so behaviour must not change; the proof
# is a hardening-smoke run immediately after apply.
#
# BinaryLane semantics (differs from Vultr): rules live on the SERVER (no group
# object) and the change_advanced_firewall_rules action REPLACES the whole rule
# list. First matching rule wins, so the last rule is an explicit drop-all.
#
# CHANGE GATE: without -Approve this is a dry run - it prints current vs desired
# rules and exits. Applying changes live networking on the box; a mis-scoped
# rule set = CI lockout (recovery = clear rules via the BinaryLane console).
#
# Idempotent: if the live rule list already equals the desired list, no-op exit 0.
# No secrets printed; the token comes from env BINARYLANE_API_TOKEN or .env.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [string]$Name = 'syd2.swordfish.cfd',
    [string[]]$AllowTcpPorts = @('22', '80', '443'),
    [switch]$Approve
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

$apiToken = Read-DotEnvValue 'BINARYLANE_API_TOKEN'
if (-not $apiToken) { throw 'BINARYLANE_API_TOKEN not found in environment or .env' }
$headers = @{ Authorization = "Bearer $apiToken" }
$base = 'https://api.binarylane.com.au/v2'

function Invoke-BinaryLane([string]$method, [string]$path, $body) {
    $args = @{ Method = $method; Uri = "$base$path"; Headers = $headers }
    if ($null -ne $body) {
        $args.Body = ($body | ConvertTo-Json -Depth 6)
        $args.ContentType = 'application/json'
    }
    try { return Invoke-RestMethod @args }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw "BinaryLane API $method $path failed: $($_.Exception.Message) $detail"
    }
}

# --- resolve server + its public IP (rules are per-server on BinaryLane) ---
$server = (Invoke-BinaryLane GET '/servers?per_page=200' $null).servers | Where-Object { $_.name -eq $Name }
if (-not $server) { throw "Server '$Name' not found in the BinaryLane account" }
$ip = ($server.networks.v4 | Where-Object { $_.type -eq 'public' } | Select-Object -First 1).ip_address
if (-not $ip) { throw "Server '$Name' has no public IPv4 address" }

# --- desired: accept the allowed TCP ports to this box, then drop everything
#     else (first match wins; the drop-all makes the provider layer default-deny
#     like the Vultr group was) ---
$desired = @(
    @{
        description           = "swordfish: allow tcp $($AllowTcpPorts -join '/')"
        protocol              = 'tcp'
        source_addresses      = @('0.0.0.0/0')
        destination_addresses = @("$ip/32")
        destination_ports     = @($AllowTcpPorts)
        action                = 'accept'
    },
    @{
        description           = 'swordfish: default deny'
        protocol              = 'all'
        source_addresses      = @('0.0.0.0/0')
        destination_addresses = @("$ip/32")
        action                = 'drop'
    }
)

$current = (Invoke-BinaryLane GET "/servers/$($server.id)/advanced_firewall_rules" $null).firewall_rules

function Format-Rule($r) {
    $ports = if ($r.destination_ports) { $r.destination_ports -join ',' } else { '*' }
    return "$($r.action) $($r.protocol) $($r.source_addresses -join ',') -> $($r.destination_addresses -join ','):$ports"
}

$currentFmt = @($current | ForEach-Object { Format-Rule $_ })
$desiredFmt = @($desired | ForEach-Object { Format-Rule $_ })

Write-Host ''
Write-Host "Server: $Name (id $($server.id), $ip)"
Write-Host 'Current provider-firewall rules:'
if ($currentFmt.Count) { $currentFmt | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  (none - provider layer wide open, ufw is the only firewall)' }
Write-Host 'Desired provider-firewall rules (ordered, first match wins):'
$desiredFmt | ForEach-Object { Write-Host "  $_" }
Write-Host ''

if (($currentFmt -join "`n") -eq ($desiredFmt -join "`n")) {
    Write-Host 'OK (no-op): provider firewall converged; nothing to do.'
    exit 0
}

if (-not $Approve) {
    Write-Host 'DRY RUN - no changes. Re-run with -Approve to apply (replaces the whole rule list;'
    Write-Host 'run the hardening-smoke workflow immediately after to prove SSH still works).'
    exit 0
}

$null = Invoke-BinaryLane POST "/servers/$($server.id)/actions" @{
    type           = 'change_advanced_firewall_rules'
    firewall_rules = $desired
}

# read back and show what the provider now enforces
$applied = (Invoke-BinaryLane GET "/servers/$($server.id)/advanced_firewall_rules" $null).firewall_rules
Write-Host 'Applied. Provider now enforces:'
$applied | ForEach-Object { Write-Host "  $(Format-Rule $_)" }
Write-Host ''
Write-Host 'Done. NEXT (verify, CI-as-hands): dispatch the hardening-smoke workflow now -'
Write-Host "  gh workflow run hardening-smoke -f host=$Name -f tls_fqdn="
Write-Host 'SSH still green through the provider firewall = converge verified.'
