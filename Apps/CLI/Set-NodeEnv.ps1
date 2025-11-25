#!/usr/bin/env pwsh
<#
    Set-NodeEnv.ps1
    - Configures npm global prefix + cache to K:\Kydras\SDKs\Node
    - Adds Node global bin path to user PATH
    - Logs and backs up previous npm config
#>

[CmdletBinding()]
param(
    [string]$NodeRoot = "K:\Kydras\SDKs\Node",
    [switch]$DryRun
)

$LogRoot = "K:\Kydras\Logs"
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile   = Join-Path $LogRoot ("Set-NodeEnv_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$BackupFile = Join-Path $LogRoot "Set-NodeEnv_backup_last.json"

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Set-NodeEnv starting (DryRun = $DryRun) ==="
Write-Log "Target NodeRoot: $NodeRoot"

# ---------- Ensure directories ----------
$dirs = @(
    $NodeRoot,
    (Join-Path $NodeRoot "npm-global"),
    (Join-Path $NodeRoot "npm-cache")
)

foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        Write-Log "Ensured directory: $d"
    } else {
        Write-Log "Exists: $d"
    }
}

# ---------- Backup existing npm config (if npm available) ----------
$npmPrefix = $null
$npmCache  = $null
try {
    $npmPrefix = (npm config get prefix) 2>$null
    $npmCache  = (npm config get cache)  2>$null
} catch {
    Write-Log "WARN: npm not found on PATH or npm config get failed."
}

$backup = [ordered]@{
    Timestamp = (Get-Date)
    Npm       = @{
        prefix = $npmPrefix
        cache  = $npmCache
    }
    UserPath  = [Environment]::GetEnvironmentVariable("Path", "User")
}

$backup | ConvertTo-Json -Depth 4 | Set-Content -Path $BackupFile -Encoding UTF8
Write-Log "Backed up npm prefix/cache and user PATH to $BackupFile"

if ($DryRun) {
    Write-Log "DryRun = $true, exiting after backup."
    Write-Host "Dry run complete. Backup saved to: $BackupFile"
    exit 0
}

# ---------- Set npm global + cache ----------
$NewPrefix = Join-Path $NodeRoot "npm-global"
$NewCache  = Join-Path $NodeRoot "npm-cache"

try {
    Write-Log "Setting npm prefix to $NewPrefix"
    npm config set prefix "$NewPrefix" | Tee-Object -FilePath $LogFile -Append

    Write-Log "Setting npm cache to $NewCache"
    npm config set cache "$NewCache" | Tee-Object -FilePath $LogFile -Append
} catch {
    Write-Log "ERROR: npm config set failed: $($_.Exception.Message)"
    Write-Error "npm config set failed. Is Node/npm installed and on PATH?"
}

# ---------- Update user PATH ----------
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }

$binPath = $NewPrefix  # npm puts global binaries in prefix on Windows

if ($userPath -notlike "*$binPath*") {
    $newUserPath = $userPath.TrimEnd(';')
    if ($newUserPath.Length -gt 0) { $newUserPath += ";" }
    $newUserPath += $binPath

    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Log "Added to user PATH: $binPath"
} else {
    Write-Log "User PATH already contains: $binPath"
}

# ---------- Final snapshot ----------
$final = [ordered]@{
    Npm = @{
        prefix = (npm config get prefix) 2>$null
        cache  = (npm config get cache)  2>$null
    }
}
$finalJson = $final | ConvertTo-Json -Depth 3
Write-Log "Final npm snapshot:`n$finalJson"

Write-Log "=== Set-NodeEnv completed. Open a NEW shell to see updated PATH. ==="
Write-Host ""
Write-Host "Done. npm now points to:"
Write-Host "  prefix = $NewPrefix"
Write-Host "  cache  = $NewCache"
Write-Host ""
Write-Host "Open a NEW PowerShell and run:"
Write-Host "  npm config get prefix"
Write-Host "  npm config get cache"
