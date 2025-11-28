# Deploy-KydrasRepoManager-v6.ps1
# Backs up and writes the known-good v6 Repo Manager script.

$ErrorActionPreference = 'Stop'

$targetPath = 'K:\Kydras\Apps\CLI\Kydras-RepoManager.ps1'

if (-not (Test-Path (Split-Path $targetPath -Parent))) {
    Write-Error "Base directory for Repo Manager does not exist: $(Split-Path $targetPath -Parent)"
}

if (Test-Path $targetPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$targetPath.bak-$ts"
    Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
    Write-Host "Backup created: $backupPath" -ForegroundColor Yellow
} else {
    Write-Host "No existing Kydras-RepoManager.ps1 found. Creating new file." -ForegroundColor Cyan
}

@'
<# 
    Kydras-RepoManager.ps1 (v6)

    Purpose:
      - Central menu for managing all Kydras repos
      - Integrates:
          1) Clone-All-KydrasRepos.ps1
          2) Run-KydrasFullPipeline.ps1
          3) Add single repo to managed list
          4) Bulk add repos from file

    Conventions:
      - Root repos folder: K:\Kydras\Repos
      - Logs:             K:\Kydras\Logs\RepoManager
      - Config:           <scriptDir>\config\managed-repos.txt
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Paths --------------------------------------------------------------

$ScriptDir  = Split-Path -Parent $PSCommandPath
$BaseDir    = $ScriptDir
$ReposRoot  = 'K:\Kydras\Repos'
$LogsRoot   = 'K:\Kydras\Logs\RepoManager'
$ConfigDir  = Join-Path $BaseDir 'config'
$RepoList   = Join-Path $ConfigDir 'managed-repos.txt'

$CloneScript     = Join-Path $BaseDir 'Clone-All-KydrasRepos.ps1'
$PipelineScript  = Join-Path $BaseDir 'Run-KydrasFullPipeline.ps1'

# --- Ensure directories -------------------------------------------------

foreach ($dir in @($ReposRoot, $LogsRoot, $ConfigDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Logging ------------------------------------------------------------

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = Join-Path $LogsRoot "RepoManager-$timestamp.log"

Start-Transcript -Path $logFile -IncludeInvocationHeader -ErrorAction SilentlyContinue | Out-Null

Write-Host "Kydras Repo Manager v6" -ForegroundColor Cyan
Write-Host "Logs: $logFile" -ForegroundColor DarkCyan
Write-Host ""

# --- Helper functions ---------------------------------------------------

function Test-GitHubToken {
    if ($env:REPLACE_WITH_SECRET_AT_RUNTIME -and $env:REPLACE_WITH_SECRET_AT_RUNTIME.Trim()) {
        Write-Host "[OK] REPLACE_WITH_SECRET_AT_RUNTIME is set." -ForegroundColor Green
        return $true
    } else {
        Write-Warning "[WARN] REPLACE_WITH_SECRET_AT_RUNTIME is not set. Some operations may fail."
        return $false
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "========= Kydras Repo Manager =========" -ForegroundColor Yellow
    Write-Host "1) Clone / refresh all Kydras repos"
    Write-Host "2) Run Full Pipeline v3 (Run-KydrasFullPipeline.ps1)"
    Write-Host "3) Add a single repo to managed list"
    Write-Host "4) Bulk add repos from file"
    Write-Host "5) Show current managed repos"
    Write-Host "Q) Quit"
    Write-Host "======================================="
    Write-Host ""
}

function Get-Input([string]$prompt) {
    Write-Host $prompt -NoNewline
    return Read-Host " "
}

function Ensure-RepoListFile {
    if (-not (Test-Path $RepoList)) {
        New-Item -ItemType File -Path $RepoList -Force | Out-Null
    }
}

function Add-RepoToList([string]$repoSpec) {
    Ensure-RepoListFile
    $repoSpec = $repoSpec.Trim()
    if ([string]::IsNullOrWhiteSpace($repoSpec)) { return }

    $existing = Get-Content $RepoList -ErrorAction SilentlyContinue
    if ($existing -contains $repoSpec) {
        Write-Host "[SKIP] Already in list: $repoSpec" -ForegroundColor DarkYellow
    } else {
        Add-Content -Path $RepoList -Value $repoSpec
        Write-Host "[ADD] $repoSpec" -ForegroundColor Green
    }
}

function Show-ManagedRepos {
    Ensure-RepoListFile
    $items = Get-Content $RepoList -ErrorAction SilentlyContinue
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "[INFO] No managed repos in list yet." -ForegroundColor DarkYellow
    } else {
        Write-Host "Managed repos:" -ForegroundColor Cyan
        $i = 1
        foreach ($line in $items) {
            Write-Host ("  {0}. {1}" -f $i, $line)
            $i++
        }
    }
}

function Invoke-CloneAll {
    if (-not (Test-Path $CloneScript)) {
        Write-Error "Clone script not found at: $CloneScript"
        return
    }
    Write-Host "[RUN] Clone-All-KydrasRepos.ps1" -ForegroundColor Cyan
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $CloneScript
}

function Invoke-FullPipeline {
    if (-not (Test-Path $PipelineScript)) {
        Write-Error "Pipeline script not found at: $PipelineScript"
        return
    }
    Write-Host "[RUN] Run-KydrasFullPipeline.ps1" -ForegroundColor Cyan
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PipelineScript `
        -ReposRoot $ReposRoot `
        -LogRoot 'K:\Kydras\Logs\FullPipeline'
}

function Bulk-AddReposFromFile {
    $defaultFile = Join-Path $ConfigDir 'bulk-repos.txt'
    Write-Host "[INFO] Expected file format per line: owner/reponame OR full git URL" -ForegroundColor DarkGray
    $path = Get-Input "Enter path to bulk repo file [`$default: $defaultFile`]:"
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $defaultFile
    }

    if (-not (Test-Path $path)) {
        Write-Error "Bulk file not found: $path"
        return
    }

    $lines = Get-Content $path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not $lines -or $lines.Count -eq 0) {
        Write-Host "[INFO] Bulk file is empty." -ForegroundColor DarkYellow
        return
    }

    foreach ($line in $lines) {
        Add-RepoToList -repoSpec $line
    }
}

# --- Main loop ----------------------------------------------------------

Test-GitHubToken | Out-Null

while ($true) {
    Show-Menu
    $selection = Get-Input "Select an option:"

    if (-not $selection) { continue }

    switch ($selection.ToUpper()) {
        '1' {
            Invoke-CloneAll
        }
        '2' {
            Invoke-FullPipeline
        }
        '3' {
            $repo = Get-Input "Enter repo (owner/name or full git URL):"
            if ($repo) {
                Add-RepoToList -repoSpec $repo
            }
        }
        '4' {
            Bulk-AddReposFromFile
        }
        '5' {
            Show-ManagedRepos
        }
        'Q' {
            Write-Host "Exiting Repo Manager." -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    }
}

Stop-Transcript | Out-Null
'@ | Set-Content -LiteralPath $targetPath -Encoding UTF8

Write-Host "Kydras-RepoManager.ps1 v6 deployed to: $targetPath" -ForegroundColor Green

