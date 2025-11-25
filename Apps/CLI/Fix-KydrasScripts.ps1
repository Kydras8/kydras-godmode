#!/usr/bin/env pwsh
<#
    Fix-KydrasScripts.ps1

    - Backs up existing:
        * Clone-All-KydrasRepos.ps1
        * Kydras-RepoBootstrap.ps1
    - Writes a canonical, fixed Clone-All-KydrasRepos.ps1 (v5.1)
      that no longer uses cloneUrl.
    - Patches Kydras-RepoBootstrap.ps1 to fix the extra ')' in the
      requirements.txt Test-Path line.

    Designed to live in: K:\Kydras\Apps\CLI
#>

[CmdletBinding()]
param(
    [string]$BaseDir = "K:\Kydras\Apps\CLI"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Fix-KydrasScripts.ps1 ===" -ForegroundColor Cyan
Write-Host ("BaseDir: {0}" -f $BaseDir) -ForegroundColor Yellow

if (-not (Test-Path $BaseDir)) {
    throw "BaseDir not found: $BaseDir"
}

$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir     = Join-Path $BaseDir ("_backup_scripts_" + $timestamp)

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$CloneScriptPath   = Join-Path $BaseDir "Clone-All-KydrasRepos.ps1"
$BootstrapScriptPath = Join-Path $BaseDir "Kydras-RepoBootstrap.ps1"

# -------------------- Backups --------------------
foreach ($f in @($CloneScriptPath, $BootstrapScriptPath)) {
    if (Test-Path $f) {
        Write-Host ("Backing up: {0}" -f $f) -ForegroundColor Yellow
        Copy-Item $f -Destination $BackupDir -Force
    } else {
        Write-Host ("[WARN] File not found (no backup): {0}" -f $f) -ForegroundColor DarkYellow
    }
}

# -------------------- Write fixed Clone-All-KydrasRepos.ps1 (v5.1) --------------------
$cloneContent = @'
#!/usr/bin/env pwsh
<#
    Clone-All-KydrasRepos.ps1 (v5.1 - canonical)

    - Clones/updates ALL repos for:
        * User:  Kydras8  (owner, public + private)
        * Org:   Kydras-Systems-Inc (optional via -IncludeOrg)
    - Destination: K:\Kydras\Repos\<repo-name>
    - Uses GitHub CLI (gh) with existing auth.
    - Idempotent: updates existing git repos, skips non-git folders.
#>

[CmdletBinding()]
param(
    [string]$Owner      = "Kydras8",
    [string]$Org        = "Kydras-Systems-Inc",
    [string]$DestRoot   = "K:\Kydras\Repos",
    [switch]$IncludeOrg = $true,
    [switch]$VerboseLogging
)

$ErrorActionPreference = "Stop"

# ---------- Paths & Logging ----------
if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
} else {
    $ScriptDir = (Get-Location).Path
}

$LogDir   = Join-Path $ScriptDir "_logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "Clone-All-KydrasRepos_$Timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "u"), $Level, $Message
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8

    if ($VerboseLogging -or $Level -ne "DEBUG") {
        Write-Host $line
    }
}

Write-Log "===== Clone-All-KydrasRepos.ps1 v5.1 starting ====="

# ---------- Pre-checks ----------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Log "GitHub CLI (gh) not found in PATH." "ERROR"
    throw "GitHub CLI (gh) is required."
}

try {
    gh auth status 2>&1 | Out-Null
    Write-Log "gh auth status OK."
}
catch {
    Write-Log "GitHub CLI is not authenticated. Run: gh auth login" "ERROR"
    throw "GitHub CLI not authenticated."
}

if (-not (Test-Path $DestRoot)) {
    Write-Log "Creating destination root: $DestRoot"
    New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
}

# ---------- Helpers ----------
function Get-GhReposForOwner {
    param(
        [Parameter(Mandatory)] [string]$GhOwner
    )

    Write-Log "Fetching repos for owner: $GhOwner"

    # Only request valid JSON fields (no cloneUrl)
    $raw = gh repo list $GhOwner --limit 500 --json name,owner,sshUrl,isPrivate,archivedAt,visibility 2>&1

    $repos = $null
    try {
        $repos = $raw | ConvertFrom-Json
    } catch {
        Write-Log "Failed to parse JSON from gh for $GhOwner" "ERROR"
        Write-Log "Raw gh output: $raw" "ERROR"
        throw
    }

    if (-not $repos) {
        Write-Log "No repositories returned for $GhOwner" "WARN"
        return @()
    }

    # Only require name (we don't depend on cloneUrl anymore)
    $valid = $repos | Where-Object { $_.name }
    Write-Log ("Owner {0}: {1} valid repos" -f $GhOwner, $valid.Count)
    return $valid
}

function Test-IsGitRepo {
    param(
        [Parameter(Mandatory)][string]$Path
    )
    return (Test-Path (Join-Path $Path ".git"))
}

function Sync-Repo {
    param(
        [Parameter(Mandatory)] $Repo,
        [Parameter(Mandatory)] [string]$DestRoot
    )

    $name      = $Repo.name
    $ownerName = $Repo.owner.login
    if (-not $ownerName) {
        # Fallback if owner.login missing
        $ownerName = "Kydras8"
    }

    $localPath = Join-Path $DestRoot $name

    Write-Log "----"
    Write-Log "Repo: $name (owner: $ownerName)"
    Write-Log "Local path: $localPath"

    if (-not (Test-Path $localPath)) {
        # Fresh clone
        Write-Log "Cloning new repo: $ownerName/$name"
        gh repo clone "$ownerName/$name" $localPath 2>&1 | Out-File -FilePath $LogFile -Append -Encoding UTF8
        return
    }

    if (-not (Test-IsGitRepo -Path $localPath)) {
        Write-Log "Existing folder is not a git repo. Skipping: $localPath" "WARN"
        return
    }

    # Pull latest
    Write-Log "Updating existing repo: $name"
    try {
        git -C $localPath pull --ff-only 2>&1 | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    catch {
        Write-Log "git pull failed for $name : $_" "ERROR"
    }
}

# ---------- Main Execution ----------
$all = @()

# User repos
$userRepos = Get-GhReposForOwner -GhOwner $Owner
if ($userRepos) { $all += $userRepos }

# Org repos (optional)
if ($IncludeOrg -and $Org) {
    $orgRepos = Get-GhReposForOwner -GhOwner $Org
    if ($orgRepos) { $all += $orgRepos }
}

if (-not $all -or $all.Count -eq 0) {
    Write-Log "No repos to process. Exiting." "WARN"
    Write-Log "===== Clone-All-KydrasRepos.ps1 v5.1 complete (no repos) ====="
    Write-Host "No repos returned from GitHub." -ForegroundColor Yellow
    Write-Host "Log: $LogFile"
    exit 0
}

# Patch missing owner.login if needed
foreach ($r in $all) {
    if (-not $r.PSObject.Properties.Match("owner").Count) {
        $r | Add-Member -NotePropertyName "owner" -NotePropertyValue @{ login = $Owner }
    } elseif (-not $r.owner.login) {
        $r.owner.login = $Owner
    }
}

Write-Log ("Total repos to sync: {0}" -f $all.Count)

foreach ($repo in $all) {
    Sync-Repo -Repo $repo -DestRoot $DestRoot
}

# ---------- Summary ----------
$dirs = Get-ChildItem $DestRoot -Directory | Where-Object { $_.Name -notlike ".*" }
Write-Log ("Local repo directories present: {0}" -f $dirs.Count)
Write-Log "===== Clone-All-KydrasRepos.ps1 v5.1 complete ====="

Write-Host ""
Write-Host "Clone-All-KydrasRepos.ps1 finished." -ForegroundColor Cyan
Write-Host ("Total local repos: {0}" -f $dirs.Count)
Write-Host ("Log: {0}" -f $LogFile)
'@

Write-Host ("Writing fixed Clone-All-KydrasRepos.ps1 -> {0}" -f $CloneScriptPath) -ForegroundColor Yellow
Set-Content -Path $CloneScriptPath -Value $cloneContent -Encoding UTF8

# -------------------- Patch Kydras-RepoBootstrap.ps1 --------------------
if (Test-Path $BootstrapScriptPath) {
    Write-Host ("Patching Kydras-RepoBootstrap.ps1 -> {0}" -f $BootstrapScriptPath) -ForegroundColor Yellow
    $content = Get-Content -Path $BootstrapScriptPath -Raw

    # Fix extra ')' in requirements.txt Test-Path line
    # From: Test-Path (Join-Path $repoPath "requirements.txt"))
    # To:   Test-Path (Join-Path $repoPath "requirements.txt")
    $fixed = $content -replace 'Test-Path\s+\(Join-Path\s+\$repoPath\s+"requirements\.txt"\)\)', 'Test-Path (Join-Path $repoPath "requirements.txt")'

    if ($fixed -ne $content) {
        Set-Content -Path $BootstrapScriptPath -Value $fixed -Encoding UTF8
        Write-Host "Patched requirements.txt Test-Path line in Kydras-RepoBootstrap.ps1" -ForegroundColor Green
    } else {
        Write-Host "[INFO] No matching buggy line found to patch in Kydras-RepoBootstrap.ps1" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[WARN] Kydras-RepoBootstrap.ps1 not found; skipping patch." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "[✓] Fix-KydrasScripts.ps1 complete." -ForegroundColor Green
Write-Host "Backups stored in: $BackupDir" -ForegroundColor Green
