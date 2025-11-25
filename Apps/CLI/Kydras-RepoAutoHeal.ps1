#!/usr/bin/env pwsh
<#
    Kydras-RepoAutoHeal.ps1
    - Attempts to fix common git repo issues in K:\Kydras\Repos:
        * missing origin remote
        * detached HEAD (tries main/master)
        * fetch failures (rebuilds origin)
    - Optional: -ForceReset to git reset --hard origin/<branch>
#>

[CmdletBinding()]
param(
    [string] = "K:\Kydras\Repos",
    [switch]
)

\Stop = "Stop"

Write-Host "=== Kydras Repo Auto-Heal ===" -ForegroundColor Cyan
Write-Host ("Root: {0}" -f \) -ForegroundColor Yellow

if (-not (Test-Path \)) {
    Write-Host "[ERROR] Root directory not found." -ForegroundColor Red
    exit 1
}

\ = Get-ChildItem \ -Directory
if (-not \ -or \.Count -eq 0) {
    Write-Host "[WARN] No repositories found." -ForegroundColor DarkYellow
    exit 0
}

foreach (\ in \) {
    \ = \.Name
    \ = \.FullName

    Write-Host "----"
    Write-Host "Healing repo: \" -ForegroundColor Yellow

    if (-not (Test-Path (Join-Path \ ".git"))) {
        Write-Host "[ERROR] Not a git repo → skipping" -ForegroundColor Red
        continue
    }

    # Branch
    \ = git -C \ rev-parse --abbrev-ref HEAD 2>\
    if (-not \) {
        Write-Host "[WARN] Unable to determine current branch." -ForegroundColor DarkYellow
    } elseif (\ -eq "HEAD") {
        Write-Host "[FIX] Detached HEAD → attempting 'main' then 'master'" -ForegroundColor Cyan
        git -C \ checkout main 2>\
        \ = git -C \ rev-parse --abbrev-ref HEAD 2>\
        if (\ -eq "HEAD") {
            git -C \ checkout master 2>\
            \ = git -C \ rev-parse --abbrev-ref HEAD 2>\
        }
    }

    # Remote
    \ = git -C \ remote get-url origin 2>\
    if (-not \) {
        Write-Host "[FIX] No origin remote → guessing GitHub URL." -ForegroundColor Cyan
        \ = "https://github.com/Kydras8/\.git"
        git -C \ remote add origin \
        Write-Host ("Added origin: {0}" -f \) -ForegroundColor Green
        \ = \
    } else {
        Write-Host ("Origin: {0}" -f \) -ForegroundColor Gray
    }

    # Fetch
    try {
        git -C \ fetch --all
        Write-Host "[OK] Fetch successful" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Fetch failed, attempting remote repair..." -ForegroundColor DarkYellow
        if (-not \) {
            \ = "https://github.com/Kydras8/\.git"
        }
        git -C \ remote remove origin 2>\
        git -C \ remote add origin \
        git -C \ fetch --all
    }

    if (\ -and \ -and \ -ne "HEAD") {
        Write-Host ("[RESET] Hard resetting to origin/{0}" -f \) -ForegroundColor Red
        git -C \ reset --hard ("origin/" + \)
    }

    Write-Host "[DONE] Repo healed: \" -ForegroundColor Green
}
