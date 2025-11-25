#!/usr/bin/env pwsh
<#
    Fix-KydrasRepoManager.ps1

    - Backs up the existing Kydras-RepoManager.ps1
    - Writes a clean, canonical version with options:
        [1] Clone / Update ALL repos
        [2] Run FULL Kydras pipeline
        [3] Scan repo health
        [4] Auto-heal repos
        [Q] Quit
#>

[CmdletBinding()]
param(
    [string]$BaseDir = "K:\Kydras\Apps\CLI"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Fix-KydrasRepoManager.ps1 ===" -ForegroundColor Cyan
Write-Host ("BaseDir: {0}" -f $BaseDir) -ForegroundColor Yellow

if (-not (Test-Path $BaseDir)) {
    throw "BaseDir not found: $BaseDir"
}

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir   = Join-Path $BaseDir ("_backup_RepoManager_" + $timestamp)
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$repoMgrPath = Join-Path $BaseDir "Kydras-RepoManager.ps1"

# ----- Backup current manager if present -----
if (Test-Path $repoMgrPath) {
    Write-Host ("Backing up existing Kydras-RepoManager.ps1 -> {0}" -f $backupDir) -ForegroundColor Yellow
    Copy-Item $repoMgrPath -Destination $backupDir -Force
} else {
    Write-Host "[INFO] No existing Kydras-RepoManager.ps1 found (nothing to back up)." -ForegroundColor DarkYellow
}

# ----- New canonical manager content -----
$repoMgrContent = @'
#!/usr/bin/env pwsh
<#
    Kydras-RepoManager.ps1

    Menu:
      [1] Clone / Update ALL repos
      [2] Run FULL Kydras pipeline
      [3] Scan repo health
      [4] Auto-heal repos
      [Q] Quit
#>

$ErrorActionPreference = "Stop"

if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
} else {
    $ScriptDir = (Get-Location).Path
}

$CloneScript    = Join-Path $ScriptDir "Clone-All-KydrasRepos.ps1"
$PipelineScript = Join-Path $ScriptDir "Run-KydrasFullPipeline.ps1"
$ScanScript     = Join-Path $ScriptDir "Kydras-RepoIntegrityScan.ps1"
$HealScript     = Join-Path $ScriptDir "Kydras-RepoAutoHeal.ps1"

function Invoke-CloneAll {
    if (-not (Test-Path $CloneScript)) {
        Write-Host "Missing Clone-All-KydrasRepos.ps1 at: $CloneScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Clone-All-KydrasRepos.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File $CloneScript
}

function Invoke-FullPipeline {
    if (-not (Test-Path $PipelineScript)) {
        Write-Host "Missing Run-KydrasFullPipeline.ps1 at: $PipelineScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Run-KydrasFullPipeline.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File $PipelineScript
}

function Invoke-Scan {
    if (-not (Test-Path $ScanScript)) {
        Write-Host "Missing Kydras-RepoIntegrityScan.ps1 at: $ScanScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Kydras-RepoIntegrityScan.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File $ScanScript
}

function Invoke-Heal {
    if (-not (Test-Path $HealScript)) {
        Write-Host "Missing Kydras-RepoAutoHeal.ps1 at: $HealScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Kydras-RepoAutoHeal.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File $HealScript
}

while ($true) {
    Write-Host ""
    Write-Host "===== Kydras Repo Manager =====" -ForegroundColor Green
    Write-Host "[1] Clone / Update ALL repos"
    Write-Host "[2] Run FULL Kydras pipeline"
    Write-Host "[3] Scan repo health"
    Write-Host "[4] Auto-heal repos"
    Write-Host "[Q] Quit"
    Write-Host "==============================="

    $choice = Read-Host "Select option"

    switch ($choice.ToUpper()) {
        "1" { Invoke-CloneAll }
        "2" { Invoke-FullPipeline }
        "3" { Invoke-Scan }
        "4" { Invoke-Heal }
        "Q" { break }
        default {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    }
}

Write-Host "Exiting Kydras-RepoManager." -ForegroundColor Cyan
'@

Write-Host ("Writing new Kydras-RepoManager.ps1 -> {0}" -f $repoMgrPath) -ForegroundColor Yellow
Set-Content -Path $repoMgrPath -Value $repoMgrContent -Encoding UTF8

Write-Host ""
Write-Host "[✓] Fix-KydrasRepoManager.ps1 complete." -ForegroundColor Green
Write-Host ("Backups stored in: {0}" -f $backupDir) -ForegroundColor Green
