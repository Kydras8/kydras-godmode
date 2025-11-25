<#
    Kydras-RepoBootstrap.ps1 (v3-build-aware)

    Purpose:
      - Per-repo bootstrap invoked by Run-KydrasFullPipeline.ps1.
      - Accepts -RepoPath and:
          * Detects common project types.
          * Logs what is done.
          * For Node projects (esp. kydras-homepage-site), runs install + build.

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

function Test-CommandExists {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    return (Get-Command -Name $Name -ErrorAction SilentlyContinue) -ne $null
}

function Invoke-NodeBuild {
    param(
        [Parameter(Mandatory)]
        [string]$RepoPath,
        [Parameter(Mandatory)]
        [string]$RepoName
    )

    $packageJsonPath  = Join-Path $RepoPath 'package.json'
    $packageLockPath  = Join-Path $RepoPath 'package-lock.json'

    if (-not (Test-Path $packageJsonPath)) {
        Write-RepoLog "[$RepoName] No package.json found; skipping Node build."
        return
    }

    if (-not (Test-CommandExists 'npm')) {
        Write-RepoLog "[$RepoName] npm command not found; cannot build Node project."
        return
    }

    Write-RepoLog "[$RepoName] Detected Node.js project (package.json present)."

    Push-Location $RepoPath
    try {
        # Choose npm ci if lockfile exists; otherwise npm install.
        if (Test-Path $packageLockPath) {
            Write-RepoLog "[$RepoName] Running: npm ci"
            npm ci 2>&1 | ForEach-Object {
                Write-RepoLog "[$RepoName] npm ci: $_"
            }
        }
        else {
            Write-RepoLog "[$RepoName] Running: npm install"
            npm install 2>&1 | ForEach-Object {
                Write-RepoLog "[$RepoName] npm install: $_"
            }
        }

        # Check if "build" script is defined in package.json
        $pkgRaw = Get-Content -Path $packageJsonPath -Raw -ErrorAction Stop
        $pkg    = $pkgRaw | ConvertFrom-Json

        $hasBuildScript = $false
        if ($pkg -and $pkg.PSObject.Properties.Name -contains 'scripts') {
            $scripts = $pkg.scripts
            if ($scripts -and $scripts.PSObject.Properties.Name -contains 'build') {
                $hasBuildScript = $true
            }
        }

        if ($hasBuildScript) {
            Write-RepoLog "[$RepoName] Running: npm run build"
            npm run build 2>&1 | ForEach-Object {
                Write-RepoLog "[$RepoName] npm run build: $_"
            }
        }
        else {
            Write-RepoLog "[$RepoName] No 'build' script defined in package.json; skipping build."
        }
    }
    catch {
        Write-RepoLog "[$RepoName] Node build failed: $_"
    }
    finally {
        Pop-Location
    }
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

# Special handling per repo
switch -Regex ($repoName) {
    'kydras-homepage-site' {
        Write-RepoLog "Special-case: kydras-homepage-site (web/site repo)."
        Invoke-NodeBuild -RepoPath $RepoPath -RepoName $repoName
    }
    'kydras-homepage' {
        Write-RepoLog "Special-case: kydras-homepage (PowerShell / infra repo)."
        # Future: lint scripts, run tests, package tools, etc.
    }
    'neo-godmode-master' {
        Write-RepoLog "Special-case: neo-godmode-master (CLI / VSIX)."
        # Future: build VSIX, update docs, etc.
    }
    Default {
        # Generic Node build for any other Node repos (safe, optional).
        if (Test-Path $packageJsonPath) {
            Write-RepoLog "Generic Node handling for repo: $repoName"
            Invoke-NodeBuild -RepoPath $RepoPath -RepoName $repoName
        }
    }
}

Write-RepoLog "Bootstrap complete for: $repoName"
exit 0
