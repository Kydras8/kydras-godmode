#!/usr/bin/env pwsh
<#
    Set-AndroidSdkEnv.ps1
    - Forces Android SDK env vars to K:\Kydras\SDKs\Android
    - Adds platform-tools to machine PATH
    - Backs up current env vars
    - Idempotent: safe to re-run
#>

[CmdletBinding()]
param(
    [string]$SdkRoot = "K:\Kydras\SDKs\Android",
    [switch]$DryRun
)

# ---------- Config ----------
$LogRoot = "K:\Kydras\Logs"
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile = Join-Path $LogRoot ("Set-AndroidSdkEnv_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$BackupFile = Join-Path $LogRoot "Set-AndroidSdkEnv_backup_last.json"

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Set-AndroidSdkEnv starting (DryRun = $DryRun) ==="
Write-Log "Target SDK root: $SdkRoot"

# ---------- Preconditions ----------
if (-not (Test-Path $SdkRoot)) {
    Write-Log "ERROR: SDK root not found at $SdkRoot"
    Write-Error "SDK root not found at $SdkRoot"
    exit 1
}

$AdbPath = Join-Path $SdkRoot "platform-tools\adb.exe"
if (-not (Test-Path $AdbPath)) {
    Write-Log "WARN: adb.exe not found at $AdbPath (platform-tools missing?)"
} else {
    Write-Log "Found adb.exe at $AdbPath"
}

# ---------- Backup current env vars ----------
$backup = [ordered]@{
    Timestamp = (Get-Date)
    Machine   = @{
        ANDROID_HOME    = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "Machine")
        ANDROID_SDK_ROOT= [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "Machine")
        Path            = [Environment]::GetEnvironmentVariable("Path", "Machine")
    }
    User      = @{
        ANDROID_HOME    = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "User")
        ANDROID_SDK_ROOT= [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "User")
        Path            = [Environment]::GetEnvironmentVariable("Path", "User")
    }
}

$backupJson = $backup | ConvertTo-Json -Depth 4
$backupJson | Set-Content -Path $BackupFile -Encoding UTF8
Write-Log "Backed up current env vars to $BackupFile"

if ($DryRun) {
    Write-Log "DryRun = $true, exiting after backup."
    Write-Host "Dry run complete. Backup saved to: $BackupFile"
    exit 0
}

# ---------- Set machine-level ANDROID_* ----------
Write-Log "Setting machine-level ANDROID_HOME and ANDROID_SDK_ROOT to $SdkRoot"

[Environment]::SetEnvironmentVariable("ANDROID_HOME",     $SdkRoot, "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $SdkRoot, "Machine")

# Clear user-level overrides so machine values win
Write-Log "Clearing user-level ANDROID_HOME and ANDROID_SDK_ROOT (to avoid conflicts)"
[Environment]::SetEnvironmentVariable("ANDROID_HOME",     $null, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $null, "User")

# ---------- Update machine PATH ----------
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$ptEntry = "$SdkRoot\platform-tools"

if ($machinePath -notlike "*$ptEntry*") {
    Write-Log "Adding platform-tools to machine PATH: $ptEntry"
    $newPath = $machinePath.TrimEnd(';') + ";" + $ptEntry
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
} else {
    Write-Log "Machine PATH already contains: $ptEntry"
}

# ---------- Final state snapshot ----------
$final = [ordered]@{
    Machine = @{
        ANDROID_HOME     = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "Machine")
        ANDROID_SDK_ROOT = [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "Machine")
    }
    User = @{
        ANDROID_HOME     = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "User")
        ANDROID_SDK_ROOT = [Environment]::GetEnvironmentVariable("ANDROID_SDK_ROOT", "User")
    }
}
$finalJson = $final | ConvertTo-Json -Depth 3
Write-Log "Final env snapshot:`n$finalJson"

Write-Log "=== Set-AndroidSdkEnv completed. NOTE: Open a NEW shell to see updated vars. ==="
Write-Host ""
Write-Host "Done. Machine-level env vars updated. Backup saved to:"
Write-Host "  $BackupFile"
Write-Host ""
Write-Host "Open a NEW PowerShell window and run:"
Write-Host '  echo $env:ANDROID_HOME'
Write-Host '  echo $env:ANDROID_SDK_ROOT'
Write-Host '  adb version'
