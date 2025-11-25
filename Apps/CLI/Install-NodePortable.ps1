#!/usr/bin/env pwsh
<#
    Install-NodePortable.ps1
    - Installs portable Node.js + npm onto K:\Kydras\SDKs\Node\nodejs
    - Configures npm prefix/cache on K:
    - Updates USER PATH (safe)
    - Logs to K:\Kydras\Logs
#>

$ErrorActionPreference = "Stop"

# ----- Base paths -----
$Base     = "K:\Kydras"
$SDKRoot  = Join-Path $Base "SDKs"
$NodeRoot = Join-Path $SDKRoot "Node"
$TempDir  = Join-Path $Base "Temp"
$LogRoot  = Join-Path $Base "Logs"

# Ensure base + intermediate dirs in correct order
foreach ($p in @($Base, $SDKRoot, $NodeRoot, $TempDir, $LogRoot)) {
    if (!(Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

$ZipPath = Join-Path $TempDir "node.zip"
$NodeUrl = "https://nodejs.org/dist/v20.18.0/node-v20.18.0-win-x64.zip"
$LogFile = Join-Path $LogRoot ("NodeInstall_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Log {
    param([string]$msg)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $msg
    Write-Host $line
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Log "=== Starting Node Portable Install ==="
Log "Base     = $Base"
Log "SDKRoot  = $SDKRoot"
Log "NodeRoot = $NodeRoot"
Log "TempDir  = $TempDir"
Log "LogRoot  = $LogRoot"

# ----- Download NodeJS ZIP -----
Log "Downloading NodeJS from $NodeUrl ..."
Invoke-WebRequest -Uri $NodeUrl -OutFile $ZipPath -UseBasicParsing
Log "Download complete: $ZipPath"

# ----- Extract NodeJS -----
$NodeHome = Join-Path $NodeRoot "nodejs"

Log "Clearing any existing NodeHome at $NodeHome ..."
if (Test-Path $NodeHome) {
    Remove-Item $NodeHome -Recurse -Force
}

Log "Expanding archive to $NodeRoot ..."
Expand-Archive -Path $ZipPath -DestinationPath $NodeRoot -Force

# Find extracted folder (node-v20.*)
$ExtractedDir = Get-ChildItem $NodeRoot | Where-Object { $_.Name -like "node-v*" } | Select-Object -First 1

if (-not $ExtractedDir) {
    Log "FATAL: Could not locate extracted Node folder under $NodeRoot"
    throw "Extraction failed - no node-v* folder found."
}

Rename-Item -Path $ExtractedDir.FullName -NewName "nodejs" -Force
Log "NodeHome set to: $NodeHome"

# ----- Configure npm prefix/cache on K: -----
$NpmGlobal = Join-Path $NodeRoot "npm-global"
$NpmCache  = Join-Path $NodeRoot "npm-cache"

foreach ($d in @($NpmGlobal, $NpmCache)) {
    if (!(Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    Log "Ensured directory: $d"
}

$npmCmd = Join-Path $NodeHome "npm.cmd"
$nodeExe = Join-Path $NodeHome "node.exe"

Log "Configuring npm prefix/cache ..."
& $npmCmd config set prefix "$NpmGlobal" | Out-File -FilePath $LogFile -Append -Encoding UTF8
& $npmCmd config set cache  "$NpmCache"  | Out-File -FilePath $LogFile -Append -Encoding UTF8

# ----- Update USER PATH -----
$UserPath = [Environment]::GetEnvironmentVariable("Path","User")
if (-not $UserPath) { $UserPath = "" }

if ($UserPath -notlike "*$NodeHome*") {
    $newUserPath = $UserPath.TrimEnd(';')
    if ($newUserPath.Length -gt 0) { $newUserPath += ";" }
    $newUserPath += "$NodeHome;$NpmGlobal"
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Log "Updated user PATH with: $NodeHome and $NpmGlobal"
} else {
    Log "User PATH already contains NodeHome."
}

# ----- Verify -----
Log "Verifying Node.exe direct:"
& $nodeExe --version    | Out-File -FilePath $LogFile -Append -Encoding UTF8

Log "Verifying npm.cmd direct:"
& $npmCmd --version     | Out-File -FilePath $LogFile -Append -Encoding UTF8

Log "=== Node Portable Install COMPLETED ==="

Write-Host ""
Write-Host "Node installed to:   $NodeHome"
Write-Host "npm prefix (global): $NpmGlobal"
Write-Host "npm cache:           $NpmCache"
Write-Host ""
Write-Host "Now open a NEW PowerShell window and run:"
Write-Host "  node -v"
Write-Host "  npm  -v"
Write-Host "  npm config get prefix"
Write-Host "  npm config get cache"
