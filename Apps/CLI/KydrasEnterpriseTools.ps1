#!/usr/bin/env pwsh
<#
KydrasEnterpriseTools.ps1

- Verifies Kydras-Enterprise-Tools.exe exists
- If missing, runs Build-KydrasEnterpriseBundle.ps1 to create it
- Shows version info (if available)
- Launches the Enterprise Tools EXE

Run from:
  K:\Kydras\Apps\CLI
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$AppsDir     = "K:\Kydras\Apps\CLI"
$BundleExe   = Join-Path $AppsDir "Kydras-Enterprise-Tools.exe"
$BuildBundle = Join-Path $AppsDir "Build-KydrasEnterpriseBundle.ps1"
$VersionFile = Join-Path $AppsDir "Kydras-Tools-Version.txt"

Write-Host "=== KydrasEnterpriseTools.ps1 ===" -ForegroundColor Cyan
Write-Host "AppsDir: $AppsDir" -ForegroundColor DarkGray

if (-not (Test-Path $AppsDir)) {
    throw "Apps directory not found: $AppsDir"
}

function Show-Status {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

function Show-Ok {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Show-Error {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

# 1) Check if the EXE exists
if (Test-Path $BundleExe) {
    Show-Ok "Found existing Kydras-Enterprise-Tools.exe:"
    Write-Host "    $BundleExe" -ForegroundColor Cyan
}
else {
    Show-Status "Kydras-Enterprise-Tools.exe not found. Expected at:"
    Write-Host "    $BundleExe" -ForegroundColor DarkYellow

    # 2) Try to rebuild via Build-KydrasEnterpriseBundle.ps1
    if (-not (Test-Path $BuildBundle)) {
        Show-Error "Build-KydrasEnterpriseBundle.ps1 not found:"
        Write-Host "    $BuildBundle" -ForegroundColor DarkRed
        throw "Cannot rebuild Enterprise Tools EXE because the build script is missing."
    }

    Show-Status "Rebuilding Enterprise Tools via Build-KydrasEnterpriseBundle.ps1..."
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $BuildBundle
    }
    catch {
        Show-Error "Build-KydrasEnterpriseBundle.ps1 failed:"
        Write-Host $_
        throw
    }

    # 3) Check again after build
    if (-not (Test-Path $BundleExe)) {
        Show-Error "Build script ran, but Kydras-Enterprise-Tools.exe still not found."
        Write-Host "Expected at: $BundleExe" -ForegroundColor DarkRed
        throw "Something blocked or renamed the EXE (AV, path rules, etc.)."
    }

    $len = (Get-Item $BundleExe).Length
    Show-Ok "Kydras-Enterprise-Tools.exe successfully built ($len bytes):"
    Write-Host "    $BundleExe" -ForegroundColor Cyan
}

# 4) Show version stamp if present
if (Test-Path $VersionFile) {
    Show-Status "Current tools version stamp:"
    Get-Content $VersionFile | ForEach-Object { "    $_" } | Write-Host
}

# 5) Launch the EXE
Show-Status "Launching Kydras-Enterprise-Tools.exe..."
try {
    Start-Process -FilePath $BundleExe
    Show-Ok "Kydras Enterprise Tools launched."
}
catch {
    Show-Error "Failed to launch Kydras-Enterprise-Tools.exe:"
    Write-Host $_
    throw
}
