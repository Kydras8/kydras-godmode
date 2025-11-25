<#
    Patch-KydrasRepoBootstrap.ps1

    Purpose:
      - Backup and replace Kydras-RepoBootstrap.ps1 with a fixed, safe v2.
      - Fixes the parse error on line 42 ("Missing closing ')' after expression").
      - Provides a generic bootstrap that:
          * Accepts -RepoPath from Run-KydrasFullPipeline.
          * Detects common project types (Node/.NET/Python/Docs).
          * Logs findings without doing heavy builds (for now).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CliDir          = 'K:\Kydras\Apps\CLI'
$BootstrapPath   = Join-Path $CliDir 'Kydras-RepoBootstrap.ps1'

if (-not (Test-Path $CliDir)) {
    Write-Host "ERROR: CLI directory not found: $CliDir"
    exit 1
}

if (-not (Test-Path $BootstrapPath)) {
    Write-Host "ERROR: Bootstrap script not found: $BootstrapPath"
    exit 1
}

# Backup existing bootstrap script
$backupPath = "$BootstrapPath.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
Copy-Item -Path $BootstrapPath -Destination $backupPath -Force
Write-Host "[OK] Backup created: $backupPath"

# New bootstrap script content
$scriptContent = @'
<#
    Kydras-RepoBootstrap.ps1 (v2-safe)

    Purpose:
      - Light-weight per-repo bootstrap invoked by Run-KydrasFullPipeline.ps1.
      - Accepts -RepoPath and:
          * Detects common project types.
          * Logs what would be done.
      - DOES NOT perform heavy builds yet (safe default).

    Called from:
      pwsh -NoProfile -ExecutionPolicy Bypass -File Kydras-RepoBootstrap.ps1 -RepoPath <repoDir>
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-RepoLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[BOOTSTRAP] $Message"
}

if (-not (Test-Path $RepoPath)) {
    Write-RepoLog "RepoPath does not exist: $RepoPath"
    exit 0
}

$repoName = Split-Path $RepoPath -Leaf
Write-RepoLog "Bootstrap starting for: $repoName"
Write-RepoLog "RepoPath: $RepoPath"

# Detect common project markers
$hasSolution      = (Get-ChildItem -Path $RepoPath -Filter '*.sln' -File -ErrorAction SilentlyContinue) -ne $null
$hasCsproj        = (Get-ChildItem -Path $RepoPath -Filter '*.csproj' -File -ErrorAction SilentlyContinue) -ne $null
$packageJsonPath  = Join-Path $RepoPath 'package.json'
$requirementsPath = Join-Path $RepoPath 'requirements.txt'
$docsDir          = Join-Path $RepoPath 'docs'

if ($hasSolution -or $hasCsproj) {
    Write-RepoLog "Detected .NET project (sln/csproj present)."
}

if (Test-Path $packageJsonPath) {
    Write-RepoLog "Detected Node.js project (package.json present)."
}

if (Test-Path $requirementsPath) {
    Write-RepoLog "Detected Python project (requirements.txt present)."
}

if (Test-Path $docsDir) {
    Write-RepoLog "Detected docs/ directory."
}

# Special placeholders for key Kydras repos
switch -Regex ($repoName) {
    'kydras-homepage-site' {
        Write-RepoLog "Special-case: kydras-homepage-site (web/site repo)."
        # Future: npm install / npm run build / deploy hooks.
    }
    'kydras-homepage' {
        Write-RepoLog "Special-case: kydras-homepage (PowerShell / infra repo)."
        # Future: lint scripts / test harness.
    }
    'neo-godmode-master' {
        Write-RepoLog "Special-case: neo-godmode-master (CLI / VSIX)."
        # Future: package VSIX, update docs, etc.
    }
    Default {
        # No special handling; generic logging only.
    }
}

Write-RepoLog "Bootstrap complete for: $repoName"
exit 0
'@

# Write new content
$scriptContent | Set-Content -Path $BootstrapPath -Encoding UTF8

Write-Host "[OK] Kydras-RepoBootstrap.ps1 has been patched successfully."
Write-Host "Next: Run Kydras-RepoManager.ps1 and use option 2 (Full Pipeline v3) to verify."
