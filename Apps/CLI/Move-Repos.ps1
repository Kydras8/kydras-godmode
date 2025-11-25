#!/usr/bin/env pwsh
<#
    Move-Repos.ps1
    - Scans common locations for git repos
    - Copies them to K:\Kydras\Repos\<RepoName>
    - Uses robocopy, does NOT delete source
    - Logs everything to K:\Kydras\Logs
#>

[CmdletBinding()]
param(
    [string]$DestRoot = "K:\Kydras\Repos",
    [switch]$DryRun
)

$LogRoot = "K:\Kydras\Logs"
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile = Join-Path $LogRoot ("Move-Repos_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Move-Repos starting (DryRun = $DryRun) ==="
Write-Log "Destination root: $DestRoot"

if (-not (Test-Path $DestRoot)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
    }
    Write-Log "Created DestRoot: $DestRoot"
}

# ---------- Source roots to scan ----------
$SourceRoots = @(
    "C:\Users\kyler\kydras-repos",
    "D:\kydras-repos",
    "C:\Users\kyler\Projects",
    "D:\Projects"
)

$repos = @()

foreach ($root in $SourceRoots) {
    if (-not (Test-Path $root)) {
        Write-Log "Skip source root (not found): $root"
        continue
    }

    Write-Log "Scanning: $root"
    $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $dirs) {
        $gitDir = Join-Path $dir.FullName ".git"
        if (Test-Path $gitDir) {
            Write-Log "Found git repo: $($dir.FullName)"
            $repos += $dir
        } else {
            Write-Log "Not a repo (no .git): $($dir.FullName)"
        }
    }
}

if ($repos.Count -eq 0) {
    Write-Log "No git repos found in source roots."
    Write-Host "No repos found in configured roots."
    exit 0
}

Write-Log "Total repos found: $($repos.Count)"

foreach ($repo in $repos) {
    $name = $repo.Name
    $src  = $repo.FullName
    $dst  = Join-Path $DestRoot $name

    Write-Log "`n--- Repo: $name ---"
    Write-Log "  SRC = $src"
    Write-Log "  DST = $dst"

    if ($DryRun) {
        Write-Host "[DRY RUN] Would copy: $src -> $dst"
        continue
    }

    if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
    }

    $logForRepo = Join-Path $LogRoot ("Move-Repos_{0}_{1:yyyyMMdd_HHmmss}.log" -f $name, (Get-Date))

    $cmd = "robocopy `"$src`" `"$dst`" /MIR /ZB /MT:8 /R:2 /W:3 /V /FFT /TEE /LOG:`"$logForRepo`""
    Write-Log "  Running: $cmd"

    $rc = robocopy $src $dst /MIR /ZB /MT:8 /R:2 /W:3 /V /FFT /TEE /LOG:"$logForRepo"
    $exitCode = $LASTEXITCODE

    Write-Log "  robocopy exit code: $exitCode"
}

Write-Log "=== Move-Repos completed ==="
Write-Host ""
Write-Host "Move-Repos completed. Logs at:"
Write-Host "  $LogRoot"
