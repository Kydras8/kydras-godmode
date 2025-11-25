<#
    Bootstrap-ManagedRepos.ps1

    Purpose:
      - Auto-generate the managed repo list used by:
          - Kydras-RepoManager.ps1
          - Run-KydrasFullPipeline.ps1
      - Scans K:\Kydras\Repos for Git repos and writes:
            <GitHubOwner>/<RepoName>
        to:
            <scriptDir>\config\managed-repos.txt

    Defaults:
      - ReposRoot  : K:\Kydras\Repos
      - GitHubOwner: Kydras8
#>

param(
    [string]$ReposRoot   = 'K:\Kydras\Repos',
    [string]$GitHubOwner = 'Kydras8'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir       = Join-Path $ScriptRoot 'config'
$ManagedListPath = Join-Path $ConfigDir 'managed-repos.txt'

if (-not (Test-Path $ReposRoot)) {
    Write-Host "ERROR: Repos root not found: $ReposRoot"
    exit 1
}

if (-not (Test-Path $ConfigDir)) {
    New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
}

Write-Host "[*] Scanning repos root: $ReposRoot"
$dirs = Get-ChildItem -Path $ReposRoot -Directory -ErrorAction Stop

$repos = @()

foreach ($d in $dirs) {
    $gitPath = Join-Path $d.FullName '.git'
    if (Test-Path $gitPath) {
        # Build slug: owner/name
        $slug = "$GitHubOwner/$($d.Name)"
        $repos += $slug
    }
    else {
        # Not a Git repo; skip silently or uncomment to see:
        # Write-Host "Skipping non-git directory: $($d.FullName)"
    }
}

$repos = $repos | Sort-Object -Unique

if ($repos.Count -eq 0) {
    Write-Host "WARNING: No Git repos found under $ReposRoot."
    Write-Host "No changes written to $ManagedListPath."
    exit 0
}

Write-Host "[*] Found $($repos.Count) Git repos."
Write-Host "[*] Writing managed list to: $ManagedListPath"

# Overwrite file with fresh list
$repos | Set-Content -Path $ManagedListPath

Write-Host "[OK] Managed repo list updated."
Write-Host "Sample entries:"
$repos | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Next:"
Write-Host "  1) Run Kydras-RepoManager.ps1"
Write-Host "  2) Option 5: Show current managed repos"
Write-Host "  3) Option 2: Run Full Pipeline v3"
