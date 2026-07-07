#!/usr/bin/env pwsh
# create-backup-bucket.ps1 - Bucket 3 (Stage 1c): per-box B2 bucket + bucket-scoped key.
# Runbook: runbooks/backup-restore.md. Runs on Windows PowerShell 5.1 and pwsh 7+.
#
# Idempotent converge (CHARTER pinned decisions 5/6):
#   - bucket swordfish-<box>-backups: private, lifecycle keeps hidden file versions
#     30 days before deleting (the oops/ransomware guard) - created if missing,
#     lifecycle converged if drifted;
#   - bucket-scoped application key swordfish-<box>-restic (blast-radius isolation:
#     it can only touch this bucket). B2 shows a key's secret exactly once, at
#     creation - it lands in gitignored inventory/secrets/, never on the console.
#     An existing key is left alone (its secret is unrecoverable); -RotateKey
#     deletes and re-creates it.
#
# KEEP THIS FILE ASCII-ONLY (PS 5.1 reads unmarked files as ANSI - see doctor.ps1).

param(
    [string]$Box = 'syd1',
    [int]$VersionRetentionDays = 30,
    [switch]$RotateKey
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$bucketName = "swordfish-$Box-backups"
$keyName    = "swordfish-$Box-restic"

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

$accountKeyId = Read-DotEnvValue 'B2_APPLICATION_KEY_ID'
$accountKey   = Read-DotEnvValue 'B2_APPLICATION_KEY'
if (-not $accountKeyId -or -not $accountKey) { throw 'B2_APPLICATION_KEY_ID / B2_APPLICATION_KEY not found in environment or .env' }

# --- authorize (the only call on the fixed endpoint; everything else uses apiUrl) ---
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${accountKeyId}:${accountKey}"))
$auth = Invoke-RestMethod -Uri 'https://api.backblazeb2.com/b2api/v2/b2_authorize_account' `
    -Headers @{ Authorization = "Basic $basic" }
$api = @{ base = $auth.apiUrl; headers = @{ Authorization = $auth.authorizationToken } }

function Invoke-B2([string]$call, $body) {
    Invoke-RestMethod -Method Post -Uri "$($api.base)/b2api/v2/$call" -Headers $api.headers `
        -Body (ConvertTo-Json -Depth 6 $body) -ContentType 'application/json'
}

# --- bucket: create if missing, converge lifecycle if drifted -----------------------
$desiredLifecycle = @(@{
    fileNamePrefix           = ''
    daysFromHidingToDeleting = $VersionRetentionDays
    daysFromUploadingToHiding = $null
})

$buckets = (Invoke-B2 'b2_list_buckets' @{ accountId = $auth.accountId; bucketName = $bucketName }).buckets
if ($buckets) {
    $bucket = $buckets[0]
    $lc = $bucket.lifecycleRules
    if ($lc -and $lc[0].daysFromHidingToDeleting -eq $VersionRetentionDays -and $bucket.bucketType -eq 'allPrivate') {
        Write-Host "OK: bucket $bucketName exists (private, versions kept $VersionRetentionDays days after delete)"
    } else {
        $bucket = Invoke-B2 'b2_update_bucket' @{
            accountId = $auth.accountId; bucketId = $bucket.bucketId
            bucketType = 'allPrivate'; lifecycleRules = $desiredLifecycle
        }
        Write-Host "CHANGED: bucket $bucketName converged (private + $VersionRetentionDays-day version retention)"
    }
} else {
    $bucket = Invoke-B2 'b2_create_bucket' @{
        accountId = $auth.accountId; bucketName = $bucketName
        bucketType = 'allPrivate'; lifecycleRules = $desiredLifecycle
    }
    Write-Host "CREATED: bucket $bucketName (private, $VersionRetentionDays-day version retention)"
}

# --- bucket-scoped key ---------------------------------------------------------------
# deleteFiles is required by restic (prune + stale-lock removal); the 30-day version
# retention above is what still protects history if this key is ever compromised.
$capabilities = @('listBuckets', 'listFiles', 'readFiles', 'writeFiles', 'deleteFiles')

$keys = (Invoke-B2 'b2_list_keys' @{ accountId = $auth.accountId; maxKeyCount = 1000 }).keys
$existing = $keys | Where-Object { $_.keyName -eq $keyName }

if ($existing -and -not $RotateKey) {
    Write-Host "OK: key $keyName exists (id $($existing.applicationKeyId)); secret was shown only at creation - use -RotateKey to replace it"
    exit 0
}
if ($existing -and $RotateKey) {
    Invoke-B2 'b2_delete_key' @{ applicationKeyId = $existing.applicationKeyId } | Out-Null
    Write-Host "ROTATED: old key $keyName deleted (id $($existing.applicationKeyId))"
}

$key = Invoke-B2 'b2_create_key' @{
    accountId = $auth.accountId; keyName = $keyName
    capabilities = $capabilities; bucketId = $bucket.bucketId
}

$secretsDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'inventory\secrets'
if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Path $secretsDir | Out-Null }
$outFile = Join-Path $secretsDir "b2-$Box-restic.env"
# restic's native B2 backend reads these exact names; ascii, LF, no BOM
$content = "B2_ACCOUNT_ID=$($key.applicationKeyId)`nB2_ACCOUNT_KEY=$($key.applicationKey)`n"
[IO.File]::WriteAllText($outFile, $content)

Write-Host "CREATED: key $keyName (id $($key.applicationKeyId)), scoped to $bucketName only"
Write-Host "Secret written to $outFile (gitignored) - it is shown nowhere else, ever."
Write-Host 'Also record it founder-side (password manager), then load CI:'
Write-Host "  gh secret set RESTIC_B2_KEY_ID --body $($key.applicationKeyId)"
Write-Host "  gh secret set RESTIC_B2_KEY    (paste the secret from the file)"
