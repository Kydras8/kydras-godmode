#!/usr/bin/env pwsh
<#
Build-KydrasFullPipeline.ps1
Creates/overwrites:

  K:\Kydras\Apps\CLI\Run-KydrasFullPipeline.ps1

That script will:
  1) Run Clone-All-KydrasRepos.ps1 (HTTPS)
  2) Run kydras-repo-manager-v4.ps1 sync
  3) Run kydras-repo-manager-v4.ps1 polish
  4) Run kydras-repo-manager-v4.ps1 push

All steps are logged to:
  K:\Kydras\Repos\_full-pipeline.log
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$BaseDir           = "K:\Kydras\Apps\CLI"
$RepoRoot          = "K:\Kydras\Repos"
$CloneAllScript    = "K:\Kydras\Apps\CLI\Clone-All-KydrasRepos.ps1"
$RepoManagerScript = "K:\Kydras\Repos\kydras-repo-manager-v4.ps1"
$PipelineScript    = Join-Path $BaseDir "Run-KydrasFullPipeline.ps1"
$LogPath           = Join-Path $RepoRoot "_full-pipeline.log"

Write-Host "=== Build-KydrasFullPipeline.ps1 ===" -ForegroundColor Cyan

# Sanity checks
foreach ($p in @(
    @{Path=$CloneAllScript;    Name="Clone-All-KydrasRepos.ps1 (HTTPS)"},
    @{Path=$RepoManagerScript; Name="kydras-repo-manager-v4.ps1 (HTTPS)"}
)) {
    if (-not (Test-Path $p.Path)) {
        throw "Required script not found: $($p.Name) at $($p.Path)"
    }
}

if (-not (Test-Path $RepoRoot)) {
    Write-Host "Creating repo root at $RepoRoot" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $RepoRoot -Force | Out-Null
}

# Content of Run-KydrasFullPipeline.ps1
$driver = @'
#!/usr/bin/env pwsh
<#
Run-KydrasFullPipeline.ps1
Sequentially runs:
  1) Clone-All-KydrasRepos.ps1 (HTTPS)
  2) kydras-repo-manager-v4.ps1 sync
  3) kydras-repo-manager-v4.ps1 polish
  4) kydras-repo-manager-v4.ps1 push

Logs to:
  K:\Kydras\Repos\_full-pipeline.log
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot          = "K:\Kydras\Repos"
$CloneAllScript    = "K:\Kydras\Apps\CLI\Clone-All-KydrasRepos.ps1"
$RepoManagerScript = "K:\Kydras\Repos\kydras-repo-manager-v4.ps1"
$Log               = Join-Path $RepoRoot "_full-pipeline.log"

function Write-PipelineLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $Log -Append
    Write-Host $Message
}

Write-PipelineLog ""
Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 START ====="

try {
    Write-PipelineLog "STEP 1: Clone-All (HTTPS) starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $CloneAllScript
    Write-PipelineLog "STEP 1: Clone-All completed."
}
catch {
    Write-PipelineLog "ERROR in Clone-All: $_"
}

try {
    Write-PipelineLog "STEP 2: Repo Manager SYNC starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript sync
    Write-PipelineLog "STEP 2: Repo Manager SYNC completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager SYNC: $_"
}

try {
    Write-PipelineLog "STEP 3: Repo Manager POLISH starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript polish
    Write-PipelineLog "STEP 3: Repo Manager POLISH completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager POLISH: $_"
}

try {
    Write-PipelineLog "STEP 4: Repo Manager PUSH starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript push
    Write-PipelineLog "STEP 4: Repo Manager PUSH completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager PUSH: $_"
}

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 COMPLETE ====="
'@

Write-Host "Writing pipeline driver to:" -ForegroundColor Yellow
Write-Host "  $PipelineScript" -ForegroundColor Yellow

Set-Content -Path $PipelineScript -Value $driver -Encoding UTF8

Write-Host ""
Write-Host "[✓] Run-KydrasFullPipeline.ps1 created/updated." -ForegroundColor Green
Write-Host "Location: $PipelineScript" -ForegroundColor Green
Write-Host "Log file: $LogPath" -ForegroundColor Yellow
1