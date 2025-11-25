#!/usr/bin/env pwsh
<#
    Clone-All-KydrasRepos.v2.ps1

    - Clones/updates ALL repos for:
        * User:  Kydras8  (owner, public + private)
        * Org:   Kydras-Systems-Inc (optional)
    - Destination: K:\Kydras\Repos\<repo-name>
    - Uses GITHUB_TOKEN from user env (PAT).
    - Idempotent: updates existing git repos, skips non-git folders.
#>

[CmdletBinding()]
param(
    [string]$Owner      = "Kydras8",
    [string]$Org        = "Kydras-Systems-Inc",
    [string]$Root       = "K:\Kydras\Repos",
    [switch]$IncludeOrg = $true
)

$ErrorActionPreference = "Stop"

# ---------- Logging ----------
$LogRoot = "K:\Kydras\Logs"
if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}
$LogFile = Join-Path $LogRoot ("Clone-ALL-KydrasRepos_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

# ---------- Preconditions ----------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not on PATH. Install Git for Windows first."
}

if (-not $env:GITHUB_TOKEN) {
    throw "GITHUB_TOKEN is not set. Set a user env var 'GITHUB_TOKEN' to your PAT and open a new PowerShell."
}

$headers = @{
    Authorization = "Bearer $($env:GITHUB_TOKEN)"
    "User-Agent"  = "$Owner-RepoSync"
}

if (-not (Test-Path $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

Log "=== Clone-All-KydrasRepos.v2 starting ==="
Log "Root      : $Root"
Log "Owner     : $Owner"
Log "Org       : $Org (IncludeOrg = $IncludeOrg)"
Log "Log file  : $LogFile"

# ---------- Helpers ----------
function Get-PagedRepos {
    param(
        [string]$BaseUrl,
        [string]$Label
    )

    $all  = @()
    $page = 1

    while ($true) {
        $url = "$BaseUrl&per_page=100&page=$page"
        Log "[$Label] Fetching page $page: $url"

        $res = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

        if (-not $res -or $res.Count -eq 0) { break }

        $all += $res
        if ($res.Count -lt 100) { break }

        $page++
    }

    Log "[$Label] Total repos fetched: $($all.Count)"
    return $all
}

# ---------- Fetch user repos (owner: Kydras8) ----------
$userBase  = "https://api.github.com/user/repos?affiliation=owner&visibility=all&sort=full_name&direction=asc"
$userRepos = Get-PagedRepos -BaseUrl $userBase -Label "user" |
             Where-Object { $_.owner.login -eq $Owner }

Log "[user] After owner filter ($Owner): $($userRepos.Count) repos"

# ---------- Fetch org repos (Kydras-Systems-Inc) ----------
$orgRepos = @()
if ($IncludeOrg) {
    try {
        $orgBase  = "https://api.github.com/orgs/$Org/repos?type=all&sort=full_name&direction=asc"
        $orgRepos = Get-PagedRepos -BaseUrl $orgBase -Label "org"
    }
    catch {
        Log "[org] WARN: Failed to list org repos: $($_.Exception.Message)"
        $orgRepos = @()
    }
}

# ---------- Combine & dedupe ----------
$allRepos = @{}
foreach ($r in $userRepos + $orgRepos) {
    $allRepos[$r.full_name] = $r
}
Log "Total unique repos (user + org): $($allRepos.Count)"

# ---------- Clone / update ----------
foreach ($entry in $allRepos.GetEnumerator()) {
    $repo = $entry.Value
    $name = $repo.name
    $full = $repo.full_name
    $url  = $repo.clone_url

    $localPath = Join-Path $Root $name

    Log "----"
    Log "Repo: $full"
    Log "Local path: $localPath"

    if (Test-Path $localPath) {
        if (Test-Path (Join-Path $localPath ".git")) {
            Log "Existing git repo found. Updating..."
            git -C $localPath fetch --all --prune 2>&1 | Tee-Object -FilePath $LogFile -Append
            git -C $localPath pull  --ff-only       2>&1 | Tee-Object -FilePath $LogFile -Append
        }
        else {
            Log "WARNING: $localPath exists but is NOT a git repo. Skipping."
        }
        continue
    }

    # Clone with PAT embedded (local only; you can scrub later with git remote set-url)
    $authUrl = $url -replace '^https://', "https://$($env:GITHUB_TOKEN)@"

    Log "Cloning from: $url"
    git clone $authUrl $localPath 2>&1 | Tee-Object -FilePath $LogFile -Append
}

Log "=== Clone-All-KydrasRepos.v2 completed ==="

# Summary
$dirs = Get-ChildItem $Root -Directory | Where-Object { $_.Name -notlike ".*" }
Log "Local repo directories: $($dirs.Count)"

Write-Host ""
Write-Host "Clone-All-KydrasRepos.v2 completed." -ForegroundColor Cyan
Write-Host "Log: $LogFile"
Write-Host "Local repos under $Root : $($dirs.Count)"
