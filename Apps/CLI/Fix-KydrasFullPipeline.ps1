#!/usr/bin/env pwsh
<#
    Fix-KydrasFullPipeline.ps1

    - Creates/updates:
        * Kydras-RepoManager.ps1
        * Run-KydrasFullPipeline.ps1
    - Backs up any existing versions into a timestamped _backup_ folder.
    - Designed to live in: K:\Kydras\Apps\CLI
#>

[CmdletBinding()]
param(
    [string]$BaseDir
)

$ErrorActionPreference = "Stop"

if (-not $BaseDir) {
    if ($PSCommandPath) {
        $BaseDir = Split-Path -Parent $PSCommandPath
    } else {
        $BaseDir = "K:\Kydras\Apps\CLI"
    }
}

Write-Host ""
Write-Host "=== Fix-KydrasFullPipeline.ps1 ===" -ForegroundColor Cyan
Write-Host ("BaseDir: {0}" -f $BaseDir) -ForegroundColor Yellow

if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir     = Join-Path $BaseDir ("_backup_" + $timestamp)
$RepoMgrTarget = Join-Path $BaseDir "Kydras-RepoManager.ps1"
$PipelineScript= Join-Path $BaseDir "Run-KydrasFullPipeline.ps1"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# --- Backups ---
foreach ($f in @($RepoMgrTarget, $PipelineScript)) {
    if (Test-Path $f) {
        Write-Host ("Backing up: {0}" -f $f) -ForegroundColor Yellow
        Copy-Item $f -Destination $BackupDir -Force
    }
}

# --- Kydras-RepoManager.ps1 content ---
$repoMgrContent = @'
#!/usr/bin/env pwsh
<#
    Kydras-RepoManager.ps1

    Simple menu:
      1) Clone/update ALL Kydras repos
      2) Run full Kydras pipeline
      Q) Quit
#>

$ErrorActionPreference = "Stop"

if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
} else {
    $ScriptDir = (Get-Location).Path
}

$CloneScript   = Join-Path $ScriptDir "Clone-All-KydrasRepos.ps1"
$FullPipeline  = Join-Path $ScriptDir "Run-KydrasFullPipeline.ps1"

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
    if (-not (Test-Path $FullPipeline)) {
        Write-Host "Missing Run-KydrasFullPipeline.ps1 at: $FullPipeline" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Run-KydrasFullPipeline.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File $FullPipeline
}

while ($true) {
    Write-Host ""
    Write-Host "===== Kydras Repo Manager =====" -ForegroundColor Green
    Write-Host "[1] Clone / Update ALL repos"
    Write-Host "[2] Run FULL Kydras pipeline"
    Write-Host "[Q] Quit"
    Write-Host "==============================="

    $choice = Read-Host "Select option"

    switch ($choice.ToUpper()) {
        "1" { Invoke-CloneAll }
        "2" { Invoke-FullPipeline }
        "Q" { break }
        default {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    }
}

Write-Host "Exiting Kydras-RepoManager." -ForegroundColor Cyan
'@

# --- Run-KydrasFullPipeline.ps1 content ---
$pipelineContent = @'
#!/usr/bin/env pwsh
<#
    Run-KydrasFullPipeline.ps1

    Orchestrates:
      1) Clone/Update all repos
      2) Run Kydras-RepoBootstrap.ps1 (if present)
      3) Run Build-KydrasRepoSync.ps1 (if present)
      4) Run KydrasFullPipeline.ps1 (if present)
#>

$ErrorActionPreference = "Stop"

if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
} else {
    $ScriptDir = (Get-Location).Path
}

$LogDir = Join-Path $ScriptDir "_logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "Run-KydrasFullPipeline_$Timestamp.log"

function Write-PipelineLog {
    param([string]$Message, [string]$Level = "INFO")

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "u"), $Level, $Message
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $line
}

function Invoke-Step {
    param(
        [string]$Name,
        [ScriptBlock]$Action
    )

    Write-PipelineLog "=== STEP: $Name ==="
    try {
        & $Action
        Write-PipelineLog "STEP OK: $Name"
    }
    catch {
        Write-PipelineLog "STEP FAILED: $Name - $_" "ERROR"
    }
}

$CloneScript    = Join-Path $ScriptDir "Clone-All-KydrasRepos.ps1"
$BootstrapScript= Join-Path $ScriptDir "Kydras-RepoBootstrap.ps1"
$BuildSync      = Join-Path $ScriptDir "Build-KydrasRepoSync.ps1"
$FullPipeline   = Join-Path $ScriptDir "KydrasFullPipeline.ps1"

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 START ====="

Invoke-Step "Clone / Update ALL repos" {
    if (-not (Test-Path $CloneScript)) {
        throw "Clone-All-KydrasRepos.ps1 not found at $CloneScript"
    }
    pwsh -ExecutionPolicy Bypass -File $CloneScript
}

Invoke-Step "Kydras-RepoBootstrap.ps1 (optional)" {
    if (Test-Path $BootstrapScript) {
        pwsh -ExecutionPolicy Bypass -File $BootstrapScript
    } else {
        Write-PipelineLog "Kydras-RepoBootstrap.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "Build-KydrasRepoSync.ps1 (optional)" {
    if (Test-Path $BuildSync) {
        pwsh -ExecutionPolicy Bypass -File $BuildSync
    } else {
        Write-PipelineLog "Build-KydrasRepoSync.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "KydrasFullPipeline.ps1 (optional)" {
    if (Test-Path $FullPipeline) {
        pwsh -ExecutionPolicy Bypass -File $FullPipeline
    } else {
        Write-PipelineLog "KydrasFullPipeline.ps1 not found, skipping." "WARN"
    }
}

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 COMPLETE ====="
Write-Host ""
Write-Host "Run-KydrasFullPipeline complete." -ForegroundColor Green
Write-Host "Log: $LogFile" -ForegroundColor Yellow
'@

Write-Host "Writing Kydras-RepoManager.ps1 -> $RepoMgrTarget" -ForegroundColor Yellow
Set-Content -Path $RepoMgrTarget -Value $repoMgrContent -Encoding UTF8

Write-Host "Writing Run-KydrasFullPipeline.ps1 -> $PipelineScript" -ForegroundColor Yellow
Set-Content -Path $PipelineScript -Value $pipelineContent -Encoding UTF8

Write-Host ""
Write-Host "[✓] Fix-KydrasFullPipeline.ps1 complete." -ForegroundColor Green
Write-Host "New files:" -ForegroundColor Green
Write-Host "  $RepoMgrTarget" -ForegroundColor Yellow
Write-Host "  $PipelineScript" -ForegroundColor Yellow
Write-Host "Backups in:" -ForegroundColor Green
Write-Host "  $BackupDir" -ForegroundColor Yellow
