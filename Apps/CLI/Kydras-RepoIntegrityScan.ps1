#!/usr/bin/env pwsh
<#
    Kydras-RepoIntegrityScan.ps1
    - Scans all repos in K:\Kydras\Repos
    - Reports:
        * missing .git
        * origin remote
        * active branch / detached HEAD
        * dirty working tree
        * fetch success
    - Logs:
        <CLI>\\_logs\\RepoStatus_<timestamp>.log
#>

[CmdletBinding()]
param(
    [string] = "K:\Kydras\Repos"
)

\Stop = "Stop"

if (\K:\Kydras\Apps\CLI\Kydras-RepoSystem-Upgrade-v3.ps1) {
    \ = Split-Path -Parent \K:\Kydras\Apps\CLI\Kydras-RepoSystem-Upgrade-v3.ps1
} else {
    \ = (Get-Location).Path
}

\ = Join-Path \ "_logs"
if (-not (Test-Path \)) {
    New-Item -ItemType Directory -Path \ -Force | Out-Null
}

\20251122_022412 = Get-Date -Format "yyyyMMdd_HHmmss"
\   = Join-Path \ ("RepoStatus_" + \20251122_022412 + ".log")

function Log {
    param([string]\)
    \ = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), \
    \ | Out-File -FilePath \ -Append
    Write-Host \
}

Log "=== Kydras Repo Integrity Scan starting ==="
Log ("Root directory: {0}" -f \)

if (-not (Test-Path \)) {
    Log "[ERROR] Root directory not found!"
    exit 1
}

\ = Get-ChildItem \ -Directory
if (-not \ -or \.Count -eq 0) {
    Log "[WARN] No repositories found."
    exit 0
}

foreach (\ in \) {
    Log "----"
    Log ("Scanning repo: {0}" -f \.Name)
    \ = \.FullName

    \ = Join-Path \ ".git"
    if (-not (Test-Path \)) {
        Log "[ERROR] Missing .git folder → NOT a valid repo"
        continue
    }

    # Remote
    \ = git -C \ remote get-url origin 2>\
    if (-not \) {
        Log "[WARN] No origin remote configured"
    } else {
        Log ("Remote: {0}" -f \)
    }

    # Branch
    \ = git -C \ rev-parse --abbrev-ref HEAD 2>\
    if (\ -eq "HEAD") {
        Log "[WARN] Detached HEAD state"
    } elseif (\) {
        Log ("Branch: {0}" -f \)
    } else {
        Log "[WARN] Unable to determine branch"
    }

    # Uncommitted changes
    \ = git -C \ status --porcelain
    if (\) {
        Log "[WARN] Repo has uncommitted changes"
    } else {
        Log "[OK] Working tree clean"
    }

    # Fetch check
    try {
        git -C \ fetch --dry-run 2>&1 | Out-Null
        Log "[OK] Git fetch successful"
    } catch {
        Log "[ERROR] Git fetch failed"
    }
}

Log "=== Scan Complete ==="
Log ("Log saved at: {0}" -f \)

Write-Host ""
Write-Host "Scan complete. Log file:" -ForegroundColor Green
Write-Host \
