<# 
    Clone-All-KydrasRepos.ps1 (v5-fixed)
    - Syncs all GitHub repos for:
        Owner: Kydras8
        Org  : Kydras-Systems-Inc
    - Uses HTTPS only (no SSH keys required)
    - Each repo goes into: K:\Kydras\Repos\<repo-name>
    - Safe for repeated runs (update existing repos, clone missing ones)
#>

[CmdletBinding()]
param(
    [string]$Owner        = "Kydras8",
    [string]$Org          = "Kydras-Systems-Inc",
    [string]$DestRoot     = "K:\Kydras\Repos",
    [switch]$IncludeOrg   = $true,
    [switch]$IncludeForks = $false,
    [switch]$IncludeMember,
    [switch]$DryRun
)

# ----------------- Logging setup -----------------
$LogDir = "K:\Kydras\Logs\Clone-All-KydrasRepos"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $LogDir "Clone-All-KydrasRepos-$Timestamp.log"

function Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message
    )
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $script:LogFile -Value $line
    Write-Host $line
}

# ----------------- GitHub API setup -----------------
$Token = $env:GH_TOKEN

if (-not $Token) {
    Log "[WARN] GH_TOKEN is not set. Only public repos will be visible via API."
} else {
    Log "[INFO] GH_TOKEN is set. Private repos for this token should be visible."
}

$script:GHHeaders = @{
    "User-Agent" = "Kydras-RepoSync"
    "Accept"     = "application/vnd.github+json"
}
if ($Token) {
    $script:GHHeaders["Authorization"] = "Bearer $Token"
}

function Invoke-GHRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [string]$Label = "gh"
    )

    try {
        Log ("[{0}] Fetching: {1}" -f $Label, $Url)
        $resp = Invoke-RestMethod -Uri $Url -Headers $script:GHHeaders -Method Get -ErrorAction Stop
        return $resp
    }
    catch {
        Log ("[ERROR] GitHub request failed for {0}: {1}" -f $Url, $_.Exception.Message)
        return @()
    }
}

function Get-GH-ReposFromUrl {
    param(
        [Parameter(Mandatory=$true)][string]$UrlBase,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $page     = 1
    $perPage  = 100
    $allRepos = @()

    while ($true) {
        # Build page URL (handle ? vs &)
        $sep = "?"
        if ($UrlBase -like "*?*") {
            $sep = "&"
        }
        $pageUrl = "{0}{1}page={2}&per_page={3}" -f $UrlBase, $sep, $page, $perPage

        Log ("[{0}] Fetching page {1}: {2}" -f $Label, $page, $pageUrl)

        $data = Invoke-GHRequest -Url $pageUrl -Label $Label

        if (-not $data) {
            Log ("[{0}] No data returned for page {1}. Stopping." -f $Label, $page)
            break
        }

        if ($data -isnot [System.Array]) {
            $data = @($data)
        }

        $valid = $data | Where-Object { $_ -and $_.name -and $_.clone_url }
        $countRaw   = $data.Count
        $countValid = $valid.Count

        Log ("[{0}] Page {1}: raw={2}, valid={3}" -f $Label, $page, $countRaw, $countValid)

        $allRepos += $valid

        if ($countRaw -lt $perPage) {
            Log ("[{0}] Last page detected (count={1})." -f $Label, $countRaw)
            break
        }

        $page++
    }

    Log ("[{0}] Total collected (valid) repos: {1}" -f $Label, $allRepos.Count)
    return $allRepos
}

# ----------------- Git helper -----------------
function Sync-Repo {
    param(
        [Parameter(Mandatory=$true)][object]$Repo,
        [Parameter(Mandatory=$true)][string]$DestRoot
    )

    $name      = $Repo.name
    $fullName  = $Repo.full_name
    $cloneUrl  = $Repo.clone_url
    $isPrivate = [bool]$Repo.private
    $branch    = if ($Repo.default_branch) { $Repo.default_branch } else { "main" }

    # Each repo gets its own folder under DestRoot (Option A)
    $targetDir = Join-Path $DestRoot $name

    Log ("--- Repo: {0} (private={1}) -> {2}" -f $fullName, $isPrivate, $targetDir)

    if ($DryRun) {
        Log "[DRYRUN] Would sync this repo (no git commands executed)."
        return
    }

    if (Test-Path $targetDir) {
        # Existing folder
        $gitDir = Join-Path $targetDir ".git"
        if (Test-Path $gitDir) {
            Log ("[UPDATE] Fetching/pulling latest for {0}" -f $fullName)
            try {
                $remoteInfo = git -C $targetDir remote -v 2>&1
                $remoteInfo -split "`n" | ForEach-Object { 
                    if ($_ -and $_.Trim()) { Log ("[git-remote] {0}" -f $_.Trim()) }
                }

                $fetchOut = git -C $targetDir fetch origin $branch 2>&1
                $fetchOut -split "`n" | ForEach-Object {
                    if ($_ -and $_.Trim()) { Log ("[git-fetch] {0}" -f $_.Trim()) }
                }

                $checkoutOut = git -C $targetDir checkout $branch 2>&1
                $checkoutOut -split "`n" | ForEach-Object {
                    if ($_ -and $_.Trim()) { Log ("[git-checkout] {0}" -f $_.Trim()) }
                }

                $pullOut = git -C $targetDir pull origin $branch 2>&1
                $pullOut -split "`n" | ForEach-Object {
                    if ($_ -and $_.Trim()) { Log ("[git-pull] {0}" -f $_.Trim()) }
                }
            }
            catch {
                Log ("[ERROR] git update failed for {0}: {1}" -f $fullName, $_.Exception.Message)
            }
        }
        else {
            Log ("[SKIP] {0}: target directory exists but is not a git repo (no .git folder)." -f $fullName)
        }
    }
    else {
        # New clone
        Log ("[CLONE] Cloning {0}" -f $fullName)
        try {
            $parentDir = Split-Path $targetDir -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }

            $cloneOut = git clone $cloneUrl $targetDir 2>&1
            $cloneOut -split "`n" | ForEach-Object {
                if ($_ -and $_.Trim()) { Log ("[git-clone] {0}" -f $_.Trim()) }
            }
        }
        catch {
            Log ("[ERROR] git clone failed for {0}: {1}" -f $fullName, $_.Exception.Message)
        }
    }
}

# ----------------- Main -----------------
Log "=== Clone-All-KydrasRepos.ps1 (v5-fixed) starting ==="
Log ("Owner        = {0}" -f $Owner)
Log ("Org          = {0}" -f $Org)
Log ("DestRoot     = {0}" -f $DestRoot)
Log ("IncludeOrg   = {0}" -f $IncludeOrg)
Log ("IncludeForks = {0}" -f $IncludeForks)
Log ("IncludeMember= {0}" -f $IncludeMember)
Log ("DryRun       = {0}" -f $DryRun)

if (-not (Test-Path $DestRoot)) {
    Log ("[INFO] DestRoot does not exist. Creating: {0}" -f $DestRoot)
    New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
}
else {
    Log ("DestRoot exists: {0}" -f $DestRoot)
}

# ---- Collect repos ----
$allRepos = @()

# User-owned repos
$userUrlBase = "https://api.github.com/user/repos?affiliation=owner"
$userRepos = Get-GH-ReposFromUrl -UrlBase $userUrlBase -Label "user"
if ($userRepos) {
    # Filter forks if requested
    if (-not $IncludeForks) {
        $countBefore = $userRepos.Count
        $userRepos = $userRepos | Where-Object { -not $_.fork }
        Log ("[user] Repos after removing forks: {0} (was {1})" -f $userRepos.Count, $countBefore)
    }
    $allRepos += $userRepos
}

# Member repos (optional)
if ($IncludeMember) {
    $memberUrlBase = "https://api.github.com/user/repos?affiliation=collaborator,organization_member"
    $memberRepos = Get-GH-ReposFromUrl -UrlBase $memberUrlBase -Label "member"
    if ($memberRepos) {
        if (-not $IncludeForks) {
            $countBefore = $memberRepos.Count
            $memberRepos = $memberRepos | Where-Object { -not $_.fork }
            Log ("[member] Repos after removing forks: {0} (was {1})" -f $memberRepos.Count, $countBefore)
        }
        $allRepos += $memberRepos
    }
}

# Org repos
if ($IncludeOrg) {
    $orgUrlBase = "https://api.github.com/orgs/$Org/repos?type=all"
    $orgRepos = Get-GH-ReposFromUrl -UrlBase $orgUrlBase -Label "org"
    if ($orgRepos) {
        if (-not $IncludeForks) {
            $countBefore = $orgRepos.Count
            $orgRepos = $orgRepos | Where-Object { -not $_.fork }
            Log ("[org] Repos after removing forks: {0} (was {1})" -f $orgRepos.Count, $countBefore)
        }
        $allRepos += $orgRepos
    }
}

# ---- De-duplicate by full_name ----
if ($allRepos.Count -gt 0) {
    $grouped = $allRepos | Group-Object -Property full_name
    $allRepos = $grouped | ForEach-Object { $_.Group[0] }
}

Log ("Total unique repos (user + org + member): {0}" -f $allRepos.Count)

# ---- Sync all ----
foreach ($repo in $allRepos) {
    if (-not $repo) { continue }
    Sync-Repo -Repo $repo -DestRoot $DestRoot
}

# ---- Summary ----
$dirs = Get-ChildItem $DestRoot -Directory | Where-Object { $_.Name -notlike ".*" }
Log ("Local repo directories: {0}" -f $dirs.Count)
Log "=== Clone-All-KydrasRepos.ps1 (v5-fixed) completed ==="

Write-Host ""
Write-Host "Clone-All-KydrasRepos.ps1 (v5-fixed) finished." -ForegroundColor Cyan
Write-Host ("Total local repos: {0}" -f $dirs.Count)
Write-Host ("Log: {0}" -f $script:LogFile)
