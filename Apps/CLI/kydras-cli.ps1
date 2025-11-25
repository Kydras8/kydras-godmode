#!/usr/bin/env pwsh
<#
kydras-cli.ps1
God-Mode CLI for Kydras GitHub + Repo Management (HTTPS Engine)

Menu:
  1) Clone all repos (user + org)  [HTTPS cloneUrl]
  2) Clone scoped repos (Kydras8 + org) [HTTPS cloneUrl]
  3) Repo Manager: SYNC   (HTTPS clone/update)
  4) Repo Manager: POLISH (LICENSE, FUNDING, README header, SECURITY)
  5) Repo Manager: PUSH   (bulk commit + push)
  6) Open Repos Folder
  7) Open Logs
  0) Exit
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# --------------------------------------------------------
# CONFIG
# --------------------------------------------------------
$RepoRoot          = "K:\Kydras\Repos"
$CloneAllScript    = "K:\Kydras\Apps\CLI\Clone-All-KydrasRepos.ps1"     # HTTPS version
$CloneUserScript   = "K:\Kydras\Apps\CLI\Clone-Kydras8Repos.ps1"       # HTTPS version
$RepoManagerScript = "K:\Kydras\Repos\kydras-repo-manager-v4.ps1"      # HTTPS version

$LogFileCloneAll   = Join-Path $RepoRoot "_clone-all-kydras-repos.log"
$LogFileRepoMgr    = Join-Path $RepoRoot "_repo-manager-log.txt"

# --------------------------------------------------------
# HELPERS
# --------------------------------------------------------

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor DarkCyan
    Write-Host "         Kydras Systems Inc. CLI" -ForegroundColor Cyan
    Write-Host "             (kydras-cli)" -ForegroundColor Cyan
    Write-Host "       HTTPS Repo Sync + Management" -ForegroundColor DarkCyan
    Write-Host "         Nothing is off limits." -ForegroundColor DarkCyan
    Write-Host "==========================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Ensure-FileExists {
    param(
        [string]$Path,
        [string]$Description
    )
    if (-not (Test-Path $Path)) {
        Write-Host ""
        Write-Host "[ERROR] $Description not found:" -ForegroundColor Red
        Write-Host "        $Path" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Fix the path or create the file, then run kydras-cli again." -ForegroundColor Yellow
        Read-Host "Press Enter to return to menu"
        return $false
    }
    return $true
}

function Run-CloneAll {
    Show-Header
    Write-Host "[1] Clone all repos (user + org) via HTTPS" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Ensure-FileExists -Path $CloneAllScript -Description "Clone-All-KydrasRepos.ps1 (HTTPS)")) {
        return
    }

    Write-Host "Running Clone-All-KydrasRepos.ps1 (HTTPS engine)..." -ForegroundColor Cyan
    Write-Host ""

    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $CloneAllScript
    }
    catch {
        Write-Host "[ERROR] Clone-All script threw an error:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Done. If something failed, check the log:" -ForegroundColor Cyan
    Write-Host "  $LogFileCloneAll" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Run-CloneUser {
    Show-Header
    Write-Host "[2] Clone scoped repos (Kydras8 + org) via HTTPS" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Ensure-FileExists -Path $CloneUserScript -Description "Clone-Kydras8Repos.ps1 (HTTPS)")) {
        return
    }

    Write-Host "Running Clone-Kydras8Repos.ps1 (HTTPS engine)..." -ForegroundColor Cyan
    Write-Host ""

    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $CloneUserScript
    }
    catch {
        Write-Host "[ERROR] Clone-Kydras8 script threw an error:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Done. Scoped HTTPS clone (Kydras8 + org) completed." -ForegroundColor Cyan
    Write-Host "Check scoped log under the Kydras8-Scoped root." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Run-RepoManager {
    param(
        [string]$Mode  # "sync", "polish", "push"
    )

    Show-Header
    Write-Host "[Repo Manager] Mode: $Mode (HTTPS-aware)" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Ensure-FileExists -Path $RepoManagerScript -Description "kydras-repo-manager-v4.ps1 (HTTPS)")) {
        return
    }

    Write-Host "Running Repo Manager ($Mode)..." -ForegroundColor Cyan
    Write-Host ""

    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript $Mode
    }
    catch {
        Write-Host "[ERROR] Repo Manager threw an error:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Repo Manager finished. Log:" -ForegroundColor Cyan
    Write-Host "  $LogFileRepoMgr" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Open-ReposFolder {
    Show-Header
    Write-Host "[Open] Repos folder" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $RepoRoot)) {
        Write-Host "[ERROR] Repo root folder does not exist:" -ForegroundColor Red
        Write-Host "        $RepoRoot" -ForegroundColor Yellow
    }
    else {
        Start-Process "explorer.exe" -ArgumentList "`"$RepoRoot`""
        Write-Host "Opened repos folder:" -ForegroundColor Cyan
        Write-Host "  $RepoRoot" -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Open-Logs {
    Show-Header
    Write-Host "[Open] Logs" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $RepoRoot)) {
        Write-Host "[ERROR] Repo root folder does not exist:" -ForegroundColor Red
        Write-Host "        $RepoRoot" -ForegroundColor Yellow
        Read-Host "Press Enter to return to menu"
        return
    }

    Start-Process "explorer.exe" -ArgumentList "`"$RepoRoot`""
    Write-Host "Opened repo root where logs reside:" -ForegroundColor Cyan
    Write-Host "  $RepoRoot" -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $LogFileCloneAll) {
        Write-Host "Clone-All HTTPS log:" -ForegroundColor Cyan
        Write-Host "  $LogFileCloneAll" -ForegroundColor Yellow
    }
    if (Test-Path $LogFileRepoMgr) {
        Write-Host "Repo Manager log:" -ForegroundColor Cyan
        Write-Host "  $LogFileRepoMgr" -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

# --------------------------------------------------------
# MAIN MENU LOOP
# --------------------------------------------------------

while ($true) {
    Show-Header
    Write-Host "Select an action:" -ForegroundColor White
    Write-Host "  1) Clone all repos (user + org, HTTPS)" -ForegroundColor Green
    Write-Host "  2) Clone scoped repos (Kydras8 + org, HTTPS)" -ForegroundColor Green
    Write-Host "  3) Repo Manager: SYNC (HTTPS)" -ForegroundColor Cyan
    Write-Host "  4) Repo Manager: POLISH" -ForegroundColor Cyan
    Write-Host "  5) Repo Manager: PUSH" -ForegroundColor Cyan
    Write-Host "  6) Open Repos Folder" -ForegroundColor Yellow
    Write-Host "  7) Open Logs" -ForegroundColor Yellow
    Write-Host "  0) Exit" -ForegroundColor Red
    Write-Host ""

    $choice = Read-Host "Enter choice (0-7)"

    switch ($choice) {
        '1' { Run-CloneAll }
        '2' { Run-CloneUser }
        '3' { Run-RepoManager -Mode "sync" }
        '4' { Run-RepoManager -Mode "polish" }
        '5' { Run-RepoManager -Mode "push" }
        '6' { Open-ReposFolder }
        '7' { Open-Logs }
        '0' { break }
        default {
            Write-Host ""
            Write-Host "Invalid choice. Try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

Write-Host ""
Write-Host "Goodbye from kydras-cli (HTTPS engine)." -ForegroundColor Cyan
