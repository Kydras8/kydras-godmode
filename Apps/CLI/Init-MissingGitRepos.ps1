<#
    Init-MissingGitRepos.ps1

    Purpose:
      - Scan managed-repos.txt and ensure each local repo folder is a real git repo.
      - For any folder that EXISTS but has NO .git directory:
          * Run: git init
      - For existing git repos: do nothing.
      - For missing folders: log and skip.

    Safe by design:
      - Does NOT add remotes.
      - Does NOT commit, pull, or push.
      - Only runs `git init` in non-git folders.

    Assumptions:
      - CLI scripts live in: K:\Kydras\Apps\CLI
      - Repos live under:   K:\Kydras\Repos\<RepoName>
      - managed-repos.txt contains entries like: Kydras8/kydras-homepage
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CliDir       = 'K:\Kydras\Apps\CLI'
$ReposRoot    = 'K:\Kydras\Repos'
$ConfigDir    = Join-Path $CliDir 'config'
$RepoListPath = Join-Path $ConfigDir 'managed-repos.txt'
$LogsRoot     = 'K:\Kydras\Logs\GitInit'

if (-not (Test-Path $CliDir)) {
    Write-Host "ERROR: CLI directory not found: $CliDir"
    exit 1
}

if (-not (Test-Path $ReposRoot)) {
    Write-Host "ERROR: Repos root not found: $ReposRoot"
    exit 1
}

if (-not (Test-Path $RepoListPath)) {
    Write-Host "ERROR: Repo list file not found: $RepoListPath"
    exit 1
}

if (-not (Test-Path $LogsRoot)) {
    New-Item -Path $LogsRoot -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile   = Join-Path $LogsRoot "Init-MissingGitRepos_$timestamp.log"

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "=== Init-MissingGitRepos started ==="

$entries = Get-Content -Path $RepoListPath -ErrorAction SilentlyContinue |
           Where-Object { $_.Trim() -ne '' }

if (-not $entries -or $entries.Count -eq 0) {
    Write-Log "Repo list is empty: $RepoListPath" 'WARN'
    Write-Log "=== Init-MissingGitRepos ended (empty list) ===" 'WARN'
    exit 0
}

foreach ($rawEntry in $entries) {
    $entry = $rawEntry.Trim()
    Write-Log "------------------------------------------------------------"
    Write-Log "Repo entry: $entry"

    if ([string]::IsNullOrWhiteSpace($entry)) {
        Write-Log "Empty entry, skipping." 'WARN'
        continue
    }

    # Map "owner/repo" -> "repo"
    $repoName = $entry
    if ($entry -like '*/*') {
        $parts = $entry.Split('/', 2)
        if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $repoName = $parts[1]
        }
    }

    $repoDir = Join-Path $ReposRoot $repoName
    Write-Log "Resolved dir: $repoDir"

    if (-not (Test-Path $repoDir)) {
        Write-Log "Repo directory does not exist, skipping." 'WARN'
        continue
    }

    $gitDir = Join-Path $repoDir '.git'
    if (Test-Path $gitDir) {
        Write-Log ".git directory already present; repo is already initialized."
        continue
    }

    # Initialize as a git repo
    Write-Log "Initializing new git repository in: $repoDir"
    Push-Location $repoDir
    try {
        git init 2>&1 | ForEach-Object {
            Write-Log ("git init: {0}" -f $_)
        }
        Write-Log "Git repo initialized successfully in $repoDir"
    }
    catch {
        $msg = "git init failed in {0}: {1}" -f $repoDir, $_
        Write-Log $msg 'ERROR'
    }
    finally {
        Pop-Location
    }
}

Write-Log "=== Init-MissingGitRepos completed ==="
Write-Host "[OK] Init-MissingGitRepos run complete. Log: $LogFile"
