#!/usr/bin/env pwsh
<#
Clone-Kydras8Repos.ps1 (HTTPS-hardened)
Clones or updates ALL repos for:
  - User:  Kydras8
  - Org:   Kydras-Systems-Inc

Stores them under:
  K:\Kydras\Repos\Kydras8-Scoped\<repo>
#>

[CmdletBinding()]
param(
    [string]  $Root  = "K:\Kydras\Repos\Kydras8-Scoped",
    [string[]]$Users = @("Kydras8","Kydras-Systems-Inc")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

$Log = Join-Path $Root "_clone-kydras8-scoped.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $Log -Append
    Write-Host $Message
}

function Ensure-Tool {
    param([string]$Name,[string]$Cmd)
    try { Invoke-Expression $Cmd | Out-Null }
    catch {
        Write-Log "ERROR: Required tool '$Name' not found."
        throw
    }
}

Ensure-Tool -Name "gh"  -Cmd "gh --version"
Ensure-Tool -Name "git" -Cmd "git --version"

try { gh auth status | Out-Null }
catch {
    Write-Host "[!] Run: gh auth login (choose HTTPS)" -ForegroundColor Yellow
    Write-Log "ERROR: gh not authenticated."
    exit 1
}

foreach ($u in $Users) {
    Write-Log "---- Fetching repos for '$u' ----"

    # USE cloneUrl FOR HTTPS
    $reposJson = gh repo list $u --limit 200 --json name,cloneUrl 2>$null
    if ([string]::IsNullOrWhiteSpace($reposJson)) {
        Write-Log "No JSON returned for '$u'."
        continue
    }

    $repos = $reposJson | ConvertFrom-Json
    if (-not $repos) {
        Write-Log "No repos parsed for '$u'."
        continue
    }

    foreach ($r in $repos) {
        $name     = $r.name
        $cloneUrl = $r.cloneUrl

        if ([string]::IsNullOrWhiteSpace($name) -or
            [string]::IsNullOrWhiteSpace($cloneUrl)) {
            Write-Log "Skipping invalid entry for '$u'."
            continue
        }

        $target = Join-Path $Root $name

        if (Test-Path $target) {
            Write-Log "Updating repo: $name"
            try { git -C $target pull | Out-File $Log -Append }
            catch { Write-Log "ERROR pulling $name : $_" }
        }
        else {
            Write-Log "Cloning new repo via HTTPS: $name"
            try { git clone $cloneUrl $target | Out-File $Log -Append }
            catch { Write-Log "ERROR cloning $name : $_" }
        }
    }

    Write-Log "---- Finished '$u' ----"
}

Write-Log "Clone-Kydras8Repos COMPLETE (HTTPS)."
Write-Host "`n[✓] Scoped clone complete. Log: $Log"
