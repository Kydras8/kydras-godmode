#!/usr/bin/env pwsh
<#
    Repair-CloneAll-Kydras.ps1

    - Backs up existing Clone-All-KydrasRepos.ps1
    - Writes a clean, canonical v6 implementation that:
        * Uses `gh repo list` for user + org
        * Clones/updates into K:\Kydras\Repos
        * Avoids the old Get-GH-ReposFromUrl / 'if' parse bug
#>

[CmdletBinding()]
param(
    [string]$BaseDir  = "K:\Kydras\Apps\CLI",
    [string]$DestRoot = "K:\Kydras\Repos"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Repair-CloneAll-Kydras.ps1 ===" -ForegroundColor Cyan
Write-Host ("BaseDir : {0}" -f $BaseDir) -ForegroundColor Yellow
Write-Host ("DestRoot: {0}" -f $DestRoot) -ForegroundColor Yellow

if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

$timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFolder = Join-Path $BaseDir ("_backup_CloneAll_" + $timestamp)
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null

$cloneScriptPath = Join-Path $BaseDir "Clone-All-KydrasRepos.ps1"

# ----- Backup old script if present -----
if (Test-Path $cloneScriptPath) {
    Write-Host ("Backing up old Clone-All-KydrasRepos.ps1 -> {0}" -f $backupFolder) -ForegroundColor Yellow
    Copy-Item $cloneScriptPath -Destination $backupFolder -Force
} else {
    Write-Host "[INFO] No existing Clone-All-KydrasRepos.ps1 found (nothing to back up)." -ForegroundColor DarkYellow
}

# ----- Canonical v6 content -----
$cloneContent = @'
#!/usr/bin/env pwsh
<#
    Clone-All-KydrasRepos.ps1 (v6 - canonical, Kydras)

    - Clones/updates ALL repos for:
        * User:  Kydras8  (public + private, via gh auth)
        * Org:   Kydras-Systems-Inc (optional via -IncludeOrg)
    - Destination: K:\Kydras\Repos\<repo-name>
    - Uses GitHub CLI `gh repo list` JSON, no custom REST helpers.
    - Idempotent: if folder exists and is a git repo → git pull, else clone.
#>

[CmdletBinding()]
param(
    [string]$Owner        = "Kydras8",
    [string]$Org          = "Kydras-Systems-Inc",
    [string]$DestRoot     = "K:\Kydras\Repos",
    [switch]$IncludeOrg   = $true,
    [switch]$IncludeForks = $false,
    [switch]$DryRun       = $false
)

$ErrorActionPreference = "Stop"

# ---------- Logging ----------
if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
} else {
    $ScriptDir = (Get-Location).Path
}

$LogDir = Join-Path $ScriptDir "_logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir ("Clone-All-KydrasRepos_" + $Timestamp + ".log")

function Write-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $line
}

Write-Log "=== Clone-All-KydrasRepos.ps1 (v6) starting ==="
Write-Log ("Owner        = {0}" -f $Owner)
Write-Log ("Org          = {0}" -f $Org)
Write-Log ("DestRoot     = {0}" -f $DestRoot)
Write-Log ("IncludeOrg   = {0}" -f [bool]$IncludeOrg)
Write-Log ("IncludeForks = {0}" -f [bool]$IncludeForks)
Write-Log ("DryRun       = {0}" -f [bool]$DryRun)

# ---------- Pre-checks ----------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Log "[ERROR] GitHub CLI 'gh' not found in PATH."
    throw "GitHub CLI 'gh' is required."
}

try {
    gh auth status 2>&1 | Out-Null
    Write-Log "[INFO] gh auth status OK."
} catch {
    Write-Log "[ERROR] gh auth not configured. Run: gh auth login"
    throw "GitHub CLI not authenticated."
}

if (-not (Test-Path $DestRoot)) {
    Write-Log ("[INFO] Creating DestRoot: {0}" -f $DestRoot)
    New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
}
Write-Log ("DestRoot exists: {0}" -f $DestRoot)

# ---------- Helpers ----------
function Get-GhReposForOwner {
    param(
        [Parameter(Mandatory)][string]$GhOwner,
        [string]$Label = "owner"
    )

    Write-Log ("[INFO] Fetching repos for {0}: {1}" -f $Label, $GhOwner)

    # Only request fields we actually use
    $raw = gh repo list $GhOwner --limit 500 --json name,owner,isPrivate,sshUrl,isFork,archivedAt,visibility 2>&1

    $repos = $null
    try {
        $repos = $raw | ConvertFrom-Json
    } catch {
        Write-Log "[ERROR] Failed to parse JSON from gh."
        Write-Log ("[ERROR] Raw output: {0}" -f $raw)
        throw
    }

    if (-not $repos) {
        Write-Log ("[WARN] No repositories returned for {0}" -f $GhOwner)
        return @()
    }

    # Ensure each has .name
    $repos = $repos | Where-Object { $_.name }

    if (-not $IncludeForks) {
        $repos = $repos | Where-Object { -not $_.isFork }
    }

    Write-Log ("[INFO] {0} repos for {1} (after filters)" -f $repos.Count, $GhOwner)
    return $repos
}

function Test-IsGitRepo {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path (Join-Path $Path ".git"))
}

function Sync-Repo {
    param(
        [Parameter(Mandatory)] $Repo,
        [Parameter(Mandatory)][string]$DestRoot
    )

    $name      = $Repo.name
    $ownerName = $Repo.owner.login
    if (-not $ownerName) { $ownerName = $Owner }

    $localPath = Join-Path $DestRoot $name

    Write-Log ("----")
    Write-Log ("Repo: {0} (owner: {1})" -f $name, $ownerName)
    Write-Log ("Local path: {0}" -f $localPath)

    if ($DryRun) {
        if (-not (Test-Path $localPath)) {
            Write-Log "[DRY-RUN] Would clone repo here."
        } elseif (-not (Test-IsGitRepo -Path $localPath)) {
            Write-Log "[DRY-RUN] Folder exists but is not a git repo; would skip."
        } else {
            Write-Log "[DRY-RUN] Would 'git pull' here."
        }
        return
    }

    if (-not (Test-Path $localPath)) {
        Write-Log "[CLONE] Cloning new repo..."
        gh repo clone ("{0}/{1}" -f $ownerName, $name) $localPath 2>&1 | Out-File -FilePath $LogFile -Append -Encoding UTF8
        return
    }

    if (-not (Test-IsGitRepo -Path $localPath)) {
        Write-Log "[WARN] Existing folder is not a git repo. Skipping."
        return
    }

    Write-Log "[PULL] Updating existing repo..."
    try {
        git -C $localPath pull --ff-only 2>&1 | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } catch {
        Write-Log ("[ERROR] git pull failed: {0}" -f $_)
    }
}

# ---------- Main Execution ----------
$all = @()

# Owner repos
$ownerRepos = Get-GhReposForOwner -GhOwner $Owner -Label "user"
if ($ownerRepos) { $all += $ownerRepos }

# Org repos (optional)
if ($IncludeOrg -and $Org) {
    $orgRepos = Get-GhReposForOwner -GhOwner $Org -Label "org"
    if ($orgRepos) { $all += $orgRepos }
}

if (-not $all -or $all.Count -eq 0) {
    Write-Log "[WARN] No repos to process. Exiting."
    Write-Log "=== Clone-All-KydrasRepos.ps1 (v6) complete (no repos) ==="
    Write-Host "No repos returned from GitHub." -ForegroundColor Yellow
    Write-Host ("Log: {0}" -f $LogFile)
    exit 0
}

# Normalize owner.login if missing
foreach ($r in $all) {
    if (-not $r.PSObject.Properties.Match("owner").Count) {
        $r | Add-Member -NotePropertyName "owner" -NotePropertyValue @{ login = $Owner }
    } elseif (-not $r.owner.login) {
        $r.owner.login = $Owner
    }
}

Write-Log ("[INFO] Total repos to sync: {0}" -f $all.Count)

foreach ($repo in $all) {
    Sync-Repo -Repo $repo -DestRoot $DestRoot
}

# ---------- Summary ----------
$dirs = Get-ChildItem $DestRoot -Directory | Where-Object { $_.Name -notlike ".*" }
Write-Log ("[INFO] Local repo directories present: {0}" -f $dirs.Count)
Write-Log "=== Clone-All-KydrasRepos.ps1 (v6) complete ==="

Write-Host ""
Write-Host "Clone-All-KydrasRepos.ps1 (v6) finished." -ForegroundColor Cyan
Write-Host ("Total local repos: {0}" -f $dirs.Count)
Write-Host ("Log: {0}" -f $LogFile)
'@

Write-Host ("Writing new canonical Clone-All-KydrasRepos.ps1 -> {0}" -f $cloneScriptPath) -ForegroundColor Yellow
Set-Content -Path $cloneScriptPath -Value $cloneContent -Encoding UTF8

Write-Host ""
Write-Host "[✓] Repair-CloneAll-Kydras.ps1 complete." -ForegroundColor Green
Write-Host ("Backup of old script (if any) is in: {0}" -f $backupFolder) -ForegroundColor Green
