#!/usr/bin/env pwsh
<#
    Set-PythonEnv.ps1
    - Configures Python user base and pip cache to K:\Kydras\SDKs\Python
    - Creates envs/, pipcache/, Scripts/ folders
    - Affects *user*-level env vars only (safe)
    - Idempotent and logs to K:\Kydras\Logs
#>

[CmdletBinding()]
param(
    [string]$PythonRoot = "K:\Kydras\SDKs\Python",
    [switch]$DryRun
)

# ---------- Setup & logging ----------
$LogRoot = "K:\Kydras\Logs"
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile   = Join-Path $LogRoot ("Set-PythonEnv_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$BackupFile = Join-Path $LogRoot "Set-PythonEnv_backup_last.json"

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Set-PythonEnv starting (DryRun = $DryRun) ==="
Write-Log "Target PythonRoot: $PythonRoot"

# ---------- Ensure directories ----------
$dirs = @(
    $PythonRoot,
    (Join-Path $PythonRoot "envs"),
    (Join-Path $PythonRoot "pipcache"),
    (Join-Path $PythonRoot "Scripts")
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

# ---------- Backup current env ----------
$backup = [ordered]@{
    Timestamp = (Get-Date)
    User      = @{
        PYTHONUSERBASE = [Environment]::GetEnvironmentVariable("PYTHONUSERBASE", "User")
        PIP_CACHE_DIR  = [Environment]::GetEnvironmentVariable("PIP_CACHE_DIR", "User")
        Path           = [Environment]::GetEnvironmentVariable("Path", "User")
    }
}

$backup | ConvertTo-Json -Depth 4 | Set-Content -Path $BackupFile -Encoding UTF8
Write-Log "Backed up user env vars to $BackupFile"

if ($DryRun) {
    Write-Log "DryRun = $true, exiting after backup."
    Write-Host "Dry run complete. Backup saved to: $BackupFile"
    exit 0
}

# ---------- Set user env vars ----------
$UserBase = $PythonRoot
$PipCache = Join-Path $PythonRoot "pipcache"
$Scripts  = Join-Path $PythonRoot "Scripts"

Write-Log "Setting user-level PYTHONUSERBASE = $UserBase"
[Environment]::SetEnvironmentVariable("PYTHONUSERBASE", $UserBase, "User")

Write-Log "Setting user-level PIP_CACHE_DIR = $PipCache"
[Environment]::SetEnvironmentVariable("PIP_CACHE_DIR", $PipCache, "User")

# ---------- Update user PATH ----------
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }

if ($userPath -notlike "*$Scripts*") {
    $newUserPath = $userPath.TrimEnd(';')
    if ($newUserPath.Length -gt 0) { $newUserPath += ";" }
    $newUserPath += $Scripts

    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Log "Added to user PATH: $Scripts"
} else {
    Write-Log "User PATH already contains: $Scripts"
}

# ---------- Final snapshot ----------
$final = [ordered]@{
    User = @{
        PYTHONUSERBASE = [Environment]::GetEnvironmentVariable("PYTHONUSERBASE", "User")
        PIP_CACHE_DIR  = [Environment]::GetEnvironmentVariable("PIP_CACHE_DIR", "User")
    }
}
$finalJson = $final | ConvertTo-Json -Depth 3
Write-Log "Final env snapshot:`n$finalJson"

Write-Log "=== Set-PythonEnv completed. Open a NEW shell to see updated vars. ==="
Write-Host ""
Write-Host "Done. User-level Python env updated. Backup saved to:"
Write-Host "  $BackupFile"
Write-Host ""
Write-Host "Open a NEW PowerShell and run:"
Write-Host '  echo $env:PYTHONUSERBASE'
Write-Host '  echo $env:PIP_CACHE_DIR'
