# set-port-blocking.ps1 - converge a BinaryLane server's OUTBOUND port-blocking.
#
# WHY THIS FILE EXISTS (learned live 2026-07-16, cost the fleet hours):
# BinaryLane ships a per-server anti-abuse filter, `networks.port_blocking`,
# ENABLED BY DEFAULT. It silently drops OUTBOUND tcp/22 (and the SMTP ports) to
# every destination. Symptoms are indistinguishable from a remote-side problem:
# `ssh` to a third-party host times out before the banner with a perfectly good
# key, and two agents independently blamed the remote, the key, and the laptop
# before anyone tested `github.com:22` as a control. THE TELL: if outbound 22
# fails to EVERY host including github.com, it is this setting, not the peer.
#
# It is a PROVIDER-API setting: cloud-init cannot express it, ufw does not show
# it (ufw's default outgoing policy still reads ALLOW), and `iptables -S OUTPUT`
# is clean - the drop happens upstream of the box. So a rebuilt box silently
# regains the block unless this script runs. That is exactly why it is here and
# not in a runbook: the provisioning folder is the only rebuild-proof home.
#
# Fleet policy (per-box, deliberate):
#   syd4 (workspace) : DISABLED - agents need egress 22 (git/ssh, Render, peers)
#   syd3 (cockpit)   : DISABLED when it drives agent work; otherwise leave on
#   syd2 (prod)      : ENABLED (default) - it is a CI-as-hands TARGET; nothing
#                      on it needs to dial out on 22. Do not loosen without a
#                      reason and a founder call.
#
# Inbound rules are NOT touched by this script - that is set-firewall.ps1.
# Disabling outbound blocking also unblocks outbound SMTP (25/465/587); on a
# box with no mail software and no untrusted workloads that is a non-issue, but
# state it out loud before running this on anything that hosts tenants.
#
# CHANGE GATE: without -Approve this is a dry run - it prints current vs desired
# and exits. Idempotent: if the live setting already matches, no-op exit 0.
# No secrets printed; the token comes from env BINARYLANE_API_TOKEN or .env.
#
# Runbook: runbooks/provision.md (Phase 2). Verified by the egress assertion in
# provisioning/checks/assert-cockpit.sh - keep the two in lockstep.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

# PARAM CONTRACT (learned the hard way while testing this very script,
# 2026-07-16): $State is a ValidateSet string, NOT a [bool]. These scripts are
# invoked from bash (`pwsh -File ...`), and bash expands `$true`/`$false` to the
# EMPTY STRING before pwsh ever sees them - so `-Enabled:$true` silently arrives
# as `-Enabled:` and binds $false. The boolean inverts with no error, and a
# "converged" no-op would actually be a wrong-way write. A ValidateSet string
# cannot be mangled by any shell and fails loudly if it is.
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('enabled', 'disabled')][string]$State,
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
    $uri = "$base$path"
    if ($null -ne $body) {
        $json = $body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType 'application/json' -Body $json
    }
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers
}

# --- resolve the server ---
$server = (Invoke-BinaryLane GET '/servers?per_page=200' $null).servers | Where-Object { $_.name -eq $Name }
if (-not $server) { throw "Server '$Name' not found in the BinaryLane account" }

$current = [bool]$server.networks.port_blocking
$desired = ($State -eq 'enabled')

Write-Host ''
Write-Host "Server: $Name (id $($server.id))"
Write-Host "Outbound port_blocking - current: $current  desired: $desired"
if ($desired) {
    Write-Host '  (enabled = provider DROPS outbound tcp/22 + SMTP from this box)'
} else {
    Write-Host '  (disabled = outbound 22/SMTP leave the box; inbound rules unchanged)'
}
Write-Host ''

if ($current -eq $desired) {
    Write-Host 'OK (no-op): outbound port-blocking already converged; nothing to do.'
    exit 0
}

if (-not $Approve) {
    Write-Host 'DRY RUN - no changes. Re-run with -Approve to apply.'
    Write-Host 'After applying, prove it from the box itself (do NOT trust the API answer):'
    Write-Host '  timeout 8 bash -c "exec 3<>/dev/tcp/github.com/22 && head -c 4 <&3"   # expect: SSH-'
    Write-Host 'or run the cockpit-smoke workflow, which asserts exactly that.'
    exit 0
}

$action = Invoke-BinaryLane POST "/servers/$($server.id)/actions" @{
    type    = 'change_port_blocking'
    enabled = $desired
}
$actionId = $action.action.id
Write-Host "Action $actionId submitted (status: $($action.action.status)); polling..."

# the action completes asynchronously - poll rather than assume (delivery-green
# is not content-true; the setting is only real once the action says completed)
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    $status = (Invoke-BinaryLane GET "/actions/$actionId" $null).action.status
    if ($status -eq 'completed') { break }
    if ($status -eq 'errored') { throw "BinaryLane action $actionId errored" }
}
if ($status -ne 'completed') { throw "BinaryLane action $actionId did not complete in time (last status: $status)" }

# read the setting back from the API - never trust the write
$after = [bool]((Invoke-BinaryLane GET "/servers/$($server.id)" $null).server.networks.port_blocking)
if ($after -ne $desired) { throw "Read-back mismatch: port_blocking is $after, expected $desired" }

Write-Host "OK: outbound port_blocking = $after (action $actionId completed, read back from the API)."
Write-Host 'Now prove it FROM THE BOX (the API answer is not the network):'
Write-Host '  timeout 8 bash -c "exec 3<>/dev/tcp/github.com/22 && head -c 4 <&3"   # expect: SSH-'
