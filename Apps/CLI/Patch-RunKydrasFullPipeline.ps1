<#
    Patch-RunKydrasFullPipeline.ps1

    Purpose:
      - Backup and replace Run-KydrasFullPipeline.ps1 with a fixed v3 version.
      - Fixes:
          * Incorrect repo path resolution (owner/repo -> repo folder).
          * PowerShell parser error on "$repoName: $_".
      - Keeps:
          * Logging to K:\Kydras\Logs\FullPipeline
          * Integration with Kydras-RepoManager.ps1 (option 2).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CliDir        = 'K:\Kydras\Apps\CLI'
$PipelinePath  = Join-Path $CliDir 'Run-KydrasFullPipeline.ps1'

if (-not (Test-Path $CliDir)) {
    Write-Host "ERROR: CLI directory not found: $CliDir"
    exit 1
}

if (-not (Test-Path $PipelinePath)) {
    Write-Host "ERROR: Pipeline script not found: $PipelinePath"
    exit 1
}

# Backup existing pipeline script
$backupPath = "$PipelinePath.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
Copy-Item -Path $PipelinePath -Destination $backupPath -Force
Write-Host "[OK] Backup created: $backupPath"

# New pipeline script content
$scriptContent = @'
<#
    Run-KydrasFullPipeline.ps1 (v3-fixed)

    Purpose:
      - Iterate over all managed repos in:
            <scriptDir>\config\managed-repos.txt
      - Map entries like:
            Kydras8/kydras-homepage
        to local folders:
            K:\Kydras\Repos\kydras-homepage
      - Optionally run per-repo bootstrap and git maintenance.

    Conventions:
      - ReposRoot      : K:\Kydras\Repos
      - Repo list file : <scriptDir>\config\managed-repos.txt
      - Logs           : K:\Kydras\Logs\FullPipeline

    Notes:
      - Safe if repo directory doesn't exist -> logs and skips.
      - Safe if .git missing -> logs and skips git ops.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths ---------------------------------------------------------------
$ScriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReposRoot     = 'K:\Kydras\Repos'
$ConfigDir     = Join-Path $ScriptRoot 'config'
$RepoListPath  = Join-Path $ConfigDir 'managed-repos.txt'
$LogsRoot      = 'K:\Kydras\Logs\FullPipeline'

if (-not (Test-Path $LogsRoot)) {
    New-Item -Path $LogsRoot -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile   = Join-Path $LogsRoot "Run-KydrasFullPipeline_$timestamp.log"

# --- Logging -------------------------------------------------------------
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

Write-Log "=== Run-KydrasFullPipeline started ==="

# --- Validate repo list --------------------------------------------------
if (-not (Test-Path $RepoListPath)) {
    Write-Log "Repo list file not found: $RepoListPath" 'ERROR'
    Write-Host "[!] Repo list file not found. Nothing to do."
    Write-Log "=== Run-KydrasFullPipeline ended (no repo list) ===" 'WARN'
    exit 1
}

$entries = Get-Content -Path $RepoListPath -ErrorAction SilentlyContinue |
           Where-Object { $_.Trim() -ne '' }

Write-Log "Repo list: $RepoListPath"

if (-not $entries -or $entries.Count -eq 0) {
    Write-Log "Repo list is empty. Nothing to do."
    Write-Host "[!] Repo list is empty: $RepoListPath"
    Write-Log "=== Run-KydrasFullPipeline ended (empty list) ===" 'WARN'
    exit 0
}

# --- Optional: discover bootstrap script ---------------------------------
# Priority: per-repo bootstrap inside repo; fallback: global next to this script.
$GlobalBootstrap = Join-Path $ScriptRoot 'Kydras-RepoBootstrap.ps1'

# --- Main loop -----------------------------------------------------------
foreach ($rawEntry in $entries) {
    Write-Log "------------------------------------------------------------"
    $entry = $rawEntry.Trim()
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

    # Check for .git
    $gitDir = Join-Path $repoDir '.git'
    if (-not (Test-Path $gitDir)) {
        Write-Log "No .git directory found (non-git repo or missing)." 'WARN'
        # We still allow bootstrap to run in case it's a non-git project you want managed.
    }

    # Locate bootstrap script (repo-local or global)
    $RepoBootstrap   = Join-Path $repoDir 'Kydras-RepoBootstrap.ps1'
    $BootstrapToRun  = $null

    if (Test-Path $RepoBootstrap) {
        $BootstrapToRun = $RepoBootstrap
    }
    elseif (Test-Path $GlobalBootstrap) {
        $BootstrapToRun = $GlobalBootstrap
    }

    if ($BootstrapToRun) {
        Write-Log "Running bootstrap: $BootstrapToRun"
        try {
            # Pass repo path as parameter if supported; otherwise the script can ignore it.
            pwsh -NoProfile -ExecutionPolicy Bypass -File $BootstrapToRun -RepoPath $repoDir
            Write-Log "Bootstrap completed for $repoName"
        }
        catch {
            $msg = "Bootstrap failed for {0}: {1}" -f $repoName, $_
            Write-Log $msg 'ERROR'
        }
    }
    else {
        Write-Log "No Kydras-RepoBootstrap.ps1 found, skipping bootstrap phase."
    }

    # --- Basic git maintenance block (optional) --------------------------
    if (Test-Path $gitDir) {
        Write-Log "Running git maintenance in $repoDir"

        Push-Location $repoDir
        try {
            try {
                git status -sb 2>&1 | ForEach-Object {
                    Write-Log ("git status: {0}" -f $_)
                }
            }
            catch {
                $msg = "git status failed in {0}: {1}" -f $repoName, $_
                Write-Log $msg 'WARN'
            }

            try {
                git fetch --all --prune 2>&1 | ForEach-Object {
                    Write-Log ("git fetch: {0}" -f $_)
                }
            }
            catch {
                $msg = "git fetch failed in {0}: {1}" -f $repoName, $_
                Write-Log $msg 'WARN'
            }

            try {
                git pull 2>&1 | ForEach-Object {
                    Write-Log ("git pull: {0}" -f $_)
                }
            }
            catch {
                $msg = "git pull failed in {0}: {1}" -f $repoName, $_
                Write-Log $msg 'WARN'
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Log "Skipping git maintenance for $repoName (no .git)."
    }
}

Write-Log "=== Run-KydrasFullPipeline completed ==="
Write-Host "[OK] Full pipeline run complete. Log: $LogFile"
'@

# Write new content to the pipeline file
$scriptContent | Set-Content -Path $PipelinePath -Encoding UTF8

Write-Host "[OK] Run-KydrasFullPipeline.ps1 has been patched successfully."
Write-Host "You can now run it via Kydras-RepoManager.ps1 (option 2)."
