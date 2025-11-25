<#
    Kydras-RepoManager.ps1 (v7a-fixed)

    Purpose:
      - Central menu for managing all Kydras repos
      - Integrates:
          1) Clone-All-KydrasRepos.ps1
          2) Run-KydrasFullPipeline.ps1
          3) Add single repo to managed list
          4) Bulk add repos from file
          5) Show current managed repos

    Conventions:
      - Root repos folder: K:\Kydras\Repos
      - Logs:             K:\Kydras\Logs\RepoManager
      - Config:           <scriptDir>\config\managed-repos.txt
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths & setup ---------------------------------------------------------
$ScriptRoot       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReposRoot        = 'K:\Kydras\Repos'
$LogsRoot         = 'K:\Kydras\Logs\RepoManager'
$ConfigDir        = Join-Path $ScriptRoot 'config'
$ManagedListPath  = Join-Path $ConfigDir 'managed-repos.txt'

# Ensure core directories exist
foreach ($p in @($ReposRoot, $LogsRoot, $ConfigDir)) {
    if (-not (Test-Path $p)) {
        New-Item -Path $p -ItemType Directory -Force | Out-Null
    }
}

# --- Logging ---------------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile   = Join-Path $LogsRoot "Kydras-RepoManager-$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "=== Kydras Repo Manager v7a-fixed started ==="

# --- Helpers ---------------------------------------------------------------
function Ensure-ManagedList {
    if (-not (Test-Path $ManagedListPath)) {
        New-Item -Path $ManagedListPath -ItemType File -Force | Out-Null
        Write-Log "Created managed repos list at $ManagedListPath"
    }
}

function Get-ManagedRepos {
    Ensure-ManagedList
    (Get-Content -Path $ManagedListPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Trim() -ne '' }) | Sort-Object -Unique
}

# --- Actions ---------------------------------------------------------------
function Invoke-CloneAllRepos {
    Write-Log "User selected: Clone / refresh all Kydras repos"

    $cloneScript = Join-Path $ScriptRoot 'Clone-All-KydrasRepos.ps1'
    if (-not (Test-Path $cloneScript)) {
        Write-Log "Missing script: $cloneScript" 'ERROR'
        Write-Host "ERROR: Clone-All-KydrasRepos.ps1 not found at $cloneScript"
        return
    }

    Write-Log "Running: $cloneScript"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $cloneScript
        Write-Log "Clone-All-KydrasRepos.ps1 completed"
    }
    catch {
        Write-Log "Clone-All-KydrasRepos.ps1 failed: $_" 'ERROR'
        Write-Host "ERROR: Clone-All-KydrasRepos.ps1 failed. See log:"
        Write-Host "  $LogFile"
    }
}

function Invoke-FullPipeline {
    Write-Log "User selected: Run Full Pipeline v3"

    $pipelineScript = Join-Path $ScriptRoot 'Run-KydrasFullPipeline.ps1'
    if (-not (Test-Path $pipelineScript)) {
        Write-Log "Missing script: $pipelineScript" 'ERROR'
        Write-Host "ERROR: Run-KydrasFullPipeline.ps1 not found at $pipelineScript"
        return
    }

    # For now we call it WITHOUT parameters until the pipeline script is updated.
    Write-Log "Running: $pipelineScript (no parameters)"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $pipelineScript
        Write-Log "Run-KydrasFullPipeline.ps1 completed"
    }
    catch {
        Write-Log "Run-KydrasFullPipeline.ps1 failed: $_" 'ERROR'
        Write-Host "ERROR: Run-KydrasFullPipeline.ps1 failed. See log:"
        Write-Host "  $LogFile"
    }
}

function Add-SingleRepo {
    Write-Log "User selected: Add a single repo to managed list"

    Ensure-ManagedList

    $repo = Read-Host "Enter repo identifier (e.g. GitHub URL or 'owner/name')"
    if ([string]::IsNullOrWhiteSpace($repo)) {
        Write-Host "No value entered. Nothing added."
        Write-Log "Add-SingleRepo aborted: empty input" 'WARN'
        return
    }

    $repo = $repo.Trim()
    $existing = Get-ManagedRepos
    if ($existing -contains $repo) {
        Write-Host "Repo already in managed list:"
        Write-Host "  $repo"
        Write-Log "Repo '$repo' already in managed list" 'WARN'
        return
    }

    Add-Content -Path $ManagedListPath -Value $repo
    Write-Host "Added repo to managed list:"
    Write-Host "  $repo"
    Write-Log "Added repo to managed list: $repo"
}

function Bulk-Add-FromFile {
    Write-Log "User selected: Bulk add repos from file"

    Ensure-ManagedList

    $path = Read-Host "Enter path to file containing one repo per line"
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "No path entered. Aborting."
        Write-Log "Bulk-Add-FromFile aborted: empty path" 'WARN'
        return
    }

    if (-not (Test-Path $path)) {
        Write-Host "File not found:"
        Write-Host "  $path"
        Write-Log "Bulk-Add-FromFile: file not found at $path" 'ERROR'
        return
    }

    $current = Get-ManagedRepos
    $newItems = @()

    Get-Content -Path $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not ($current -contains $line)) {
            $newItems += $line
        }
    }

    if ($newItems.Count -eq 0) {
        Write-Host "No new repos to add. All entries already present or file empty."
        Write-Log "Bulk-Add-FromFile: no new repos to add" 'WARN'
        return
    }

    $newItems | Add-Content -Path $ManagedListPath
    Write-Host "Added $($newItems.Count) repos to managed list."
    Write-Log "Bulk-Add-FromFile: added $($newItems.Count) repos"
}

function Show-ManagedRepos {
    Write-Log "User selected: Show current managed repos"

    $repos = Get-ManagedRepos
    if (-not $repos -or $repos.Count -eq 0) {
        Write-Host "No managed repos configured yet."
        Write-Log "Show-ManagedRepos: list empty"
        return
    }

    Write-Host ""
    Write-Host "=== Managed Kydras Repos ==="
    $i = 1
    foreach ($r in $repos) {
        Write-Host ("{0,3}) {1}" -f $i, $r)
        $i++
    }
    Write-Host "============================"
}

# --- Menu UI ---------------------------------------------------------------
function Show-Menu {
    Write-Host ""
    Write-Host "========= Kydras Repo Manager ========="
    Write-Host "Root Repos Folder : $ReposRoot"
    Write-Host "Log File          : $LogFile"
    Write-Host "---------------------------------------"
    Write-Host "1) Clone / refresh all Kydras repos"
    Write-Host "2) Run Full Pipeline v3 (Run-KydrasFullPipeline.ps1)"
    Write-Host "3) Add a single repo to managed list"
    Write-Host "4) Bulk add repos from file"
    Write-Host "5) Show current managed repos"
    Write-Host "Q) Quit"
    Write-Host "======================================="
}

# --- Main loop -------------------------------------------------------------
do {
    Show-Menu
    $choice = Read-Host "Select an option"

    if ($null -eq $choice) {
        $choice = ''
    }

    switch ($choice.ToUpper()) {
        '1' { Invoke-CloneAllRepos }
        '2' { Invoke-FullPipeline }
        '3' { Add-SingleRepo }
        '4' { Bulk-Add-FromFile }
        '5' { Show-ManagedRepos }
        'Q' {
            Write-Log "User selected Quit. Exiting."
            break
        }
        default {
            Write-Host "Invalid selection. Please choose 1, 2, 3, 4, 5 or Q."
        }
    }
}
while ($true)

Write-Log "=== Kydras Repo Manager v7a-fixed ended ==="
