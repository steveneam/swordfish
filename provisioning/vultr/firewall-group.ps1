# firewall-group.ps1 - Bucket 2 pre-step (Checkpoint-1 amendment 1): provider-side
# firewall for syd1 allowing TCP 22/80/443 only, from anywhere, v4 + v6.
# Runbook: CHARTER.md Bucket 2 pre-steps. Runs on Windows PowerShell 5.1 and pwsh 7+.
#
# Why a Vultr firewall group when ufw already exists: Docker publishes ports via
# iptables ahead of ufw's chains, so a container port can be reachable even when
# ufw never allowed it. The provider firewall sits outside the OS - Docker cannot
# bypass it. Rules mirror ufw (22/80/443) so behaviour must not change; the proof
# is a hardening-smoke run immediately after attach.
#
# CHANGE GATE: without -Approve this is a dry run - it prints the converge plan
# (group to create, rules to add, instance to attach) and exits. Attaching changes
# live networking on syd1; mis-scoped rules = CI lockout, hence the gate.
#
# Idempotent: existing group / rules / attachment are recognised and skipped;
# re-running on a converged account prints all-OK and exits 0.
# No secrets printed; the API key comes from env VULTR_API_KEY or the gitignored .env.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [string]$GroupDescription = 'swordfish-syd1',
    [string]$InstanceLabel = 'syd1',
    [int[]]$AllowTcpPorts = @(22, 80, 443),
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

# --- desired rules: each allowed TCP port, from anywhere, v4 and v6 ---
$desired = @()
foreach ($port in $AllowTcpPorts) {
    $desired += @{ ip_type = 'v4'; protocol = 'tcp'; subnet = '0.0.0.0'; subnet_size = 0; port = "$port" }
    $desired += @{ ip_type = 'v6'; protocol = 'tcp'; subnet = '::';      subnet_size = 0; port = "$port" }
}

# --- current state ---
$group = (Invoke-Vultr GET '/firewalls?per_page=500' $null).firewall_groups |
    Where-Object { $_.description -eq $GroupDescription }

$existingRules = @()
if ($group) {
    $existingRules = (Invoke-Vultr GET "/firewalls/$($group.id)/rules?per_page=500" $null).firewall_rules
}

$instance = (Invoke-Vultr GET '/instances?per_page=500' $null).instances |
    Where-Object { $_.label -eq $InstanceLabel }
if (-not $instance) { throw "Instance '$InstanceLabel' not found in the Vultr account" }

function Test-RulePresent($rule) {
    foreach ($e in $existingRules) {
        if ($e.ip_type -eq $rule.ip_type -and $e.protocol -eq $rule.protocol -and
            $e.subnet -eq $rule.subnet -and [int]$e.subnet_size -eq [int]$rule.subnet_size -and
            "$($e.port)" -eq "$($rule.port)") { return $true }
    }
    return $false
}

$missing = @($desired | Where-Object { -not (Test-RulePresent $_) })
$attached = ($instance.firewall_group_id -and $group -and $instance.firewall_group_id -eq $group.id)

# --- plan ---
Write-Host ''
Write-Host 'Converge plan:'
if ($group) { Write-Host "  group  : OK - '$GroupDescription' exists ($($group.id))" }
else        { Write-Host "  group  : CREATE '$GroupDescription'" }
foreach ($r in $desired) {
    $state = 'ADD'
    if ($group -and (Test-RulePresent $r)) { $state = 'OK ' }
    Write-Host "  rule   : $state tcp/$($r.port) from anywhere ($($r.ip_type))"
}
if ($existingRules) {
    $unexpected = @($existingRules | Where-Object {
        $e = $_; -not (@($desired | Where-Object {
            $_.ip_type -eq $e.ip_type -and $_.protocol -eq $e.protocol -and
            $_.subnet -eq $e.subnet -and [int]$_.subnet_size -eq [int]$e.subnet_size -and
            "$($_.port)" -eq "$($e.port)" }).Count -gt 0)
    })
    foreach ($u in $unexpected) {
        Write-Host "  rule   : WARN unexpected existing rule $($u.protocol)/$($u.port) ($($u.ip_type)) - review manually, not auto-removed"
    }
}
if ($attached) { Write-Host "  attach : OK - already attached to '$InstanceLabel' ($($instance.id))" }
else           { Write-Host "  attach : ATTACH group to '$InstanceLabel' ($($instance.id), $($instance.main_ip))" }
Write-Host ''

if ($group -and $missing.Count -eq 0 -and $attached) {
    Write-Host 'OK (no-op): firewall group converged; nothing to do.'
    exit 0
}

if (-not $Approve) {
    Write-Host 'DRY RUN - no changes. Re-run with -Approve to apply (attach changes live networking on the box;'
    Write-Host 'run the hardening-smoke workflow immediately after to prove SSH still works).'
    exit 0
}

# --- apply ---
if (-not $group) {
    $group = (Invoke-Vultr POST '/firewalls' @{ description = $GroupDescription }).firewall_group
    Write-Host "Created firewall group $($group.id)"
    $existingRules = @()
    $missing = $desired
}

foreach ($r in $missing) {
    $null = Invoke-Vultr POST "/firewalls/$($group.id)/rules" $r
    Write-Host "Added rule: tcp/$($r.port) from anywhere ($($r.ip_type))"
}

# re-read and show the group's final rule set before touching the instance
$finalRules = (Invoke-Vultr GET "/firewalls/$($group.id)/rules?per_page=500" $null).firewall_rules
Write-Host ''
Write-Host "Group '$GroupDescription' final rules:"
$finalRules | ForEach-Object { Write-Host "  $($_.action) $($_.protocol)/$($_.port) $($_.subnet)/$($_.subnet_size) ($($_.ip_type))" }

if (-not $attached) {
    $null = Invoke-Vultr PATCH "/instances/$($instance.id)" @{ firewall_group_id = $group.id }
    Write-Host ''
    Write-Host "Attached group to '$InstanceLabel' ($($instance.main_ip))."
}

Write-Host ''
Write-Host 'Done. NEXT (verify, CI-as-hands): dispatch the hardening-smoke workflow now -'
Write-Host '  gh workflow run hardening-smoke'
Write-Host 'SSH still green through the provider firewall = converge verified.'
