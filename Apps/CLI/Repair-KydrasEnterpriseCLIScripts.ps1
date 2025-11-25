<# 
    Repair-KydrasEnterpriseCLIScripts.ps1

    Purpose:
      - Backup and replace core CLI scripts:
          * Update-KydrasEnterpriseCLI.ps1
          * Kydras-RepoManager.ps1
          * Run-KydrasFullPipeline.ps1
      - Enforce directory layout and logging folders
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Core Paths --------------------------------------------------------------

$AppsDir          = 'K:\Kydras\Apps\CLI'
$LogsRoot         = 'K:\Kydras\Logs'
$RepoManagerLogs  = Join-Path $LogsRoot 'RepoManager'
$PipelineLogs     = Join-Path $LogsRoot 'FullPipeline'
$ConfigDir        = Join-Path $AppsDir 'config'

$FilesToBackup = @(
    'Update-KydrasEnterpriseCLI.ps1',
    'Kydras-RepoManager.ps1',
    'Run-KydrasFullPipeline.ps1'
)

Write-Host "=== Kydras Enterprise CLI Script Repair ===" -ForegroundColor Cyan
Write-Host "[*] AppsDir: $AppsDir"

# Ensure base directories exist
foreach ($dir in @($AppsDir, $LogsRoot, $RepoManagerLogs, $PipelineLogs, $ConfigDir)) {
    if (-not (Test-Path $dir)) {
        Write-Host "[+] Creating directory: $dir"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Backup old scripts ------------------------------------------------------

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupRoot = Join-Path $AppsDir 'Backups'
$BackupDir  = Join-Path $BackupRoot "pre-repair-$timestamp"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

Write-Host "[*] Backup directory: $BackupDir"

foreach ($file in $FilesToBackup) {
    $src = Join-Path $AppsDir $file
    if (Test-Path $src) {
        Write-Host "[+] Backing up $file"
        Copy-Item $src $BackupDir -Force
    }
    else {
        Write-Host "[!] $file not found (nothing to backup)" -ForegroundColor Yellow
    }
}

# --- New script content: Update-KydrasEnterpriseCLI.ps1 ----------------------

$updateScript = @'
<# 
    Update-KydrasEnterpriseCLI.ps1 (schema-safe)

    Purpose:
      - Bump version (Major / Minor / Patch / Build)
      - Maintain a stable JSON schema:
            {
              "major": 1,
              "minor": 0,
              "patch": 0,
              "build": 0,
              "lastUpdated": "ISO-8601"
            }
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Major','Minor','Patch','Build')]
    [string]$Bump = 'Patch',

    [Parameter(Mandatory = $false)]
    [string]$Message = 'Kydras Enterprise CLI version update'
)

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $PSCommandPath
$VersionFile = Join-Path $ScriptDir 'version.json'

function New-DefaultVersionObject {
    param()

    return [pscustomobject]@{
        major       = 1
        minor       = 0
        patch       = 0
        build       = 0
        lastUpdated = (Get-Date).ToString('o')
    }
}

function Ensure-VersionSchema {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Version
    )

    if (-not $Version.PSObject.Properties.Match('major')) {
        Add-Member -InputObject $Version -MemberType NoteProperty -Name 'major' -Value 1
    }
    if (-not $Version.PSObject.Properties.Match('minor')) {
        Add-Member -InputObject $Version -MemberType NoteProperty -Name 'minor' -Value 0
    }
    if (-not $Version.PSObject.Properties.Match('patch')) {
        Add-Member -InputObject $Version -MemberType NoteProperty -Name 'patch' -Value 0
    }
    if (-not $Version.PSObject.Properties.Match('build')) {
        Add-Member -InputObject $Version -MemberType NoteProperty -Name 'build' -Value 0
    }
    if (-not $Version.PSObject.Properties.Match('lastUpdated')) {
        Add-Member -InputObject $Version -MemberType NoteProperty -Name 'lastUpdated' -Value (Get-Date).ToString('o')
    }

    return $Version
}

function Get-VersionObject {
    if (-not (Test-Path $VersionFile)) {
        Write-Host "[!] version.json not found, creating a default one..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    $raw = Get-Content $VersionFile -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Host "[!] version.json is empty, using default values..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    try {
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "[!] version.json is invalid JSON, replacing with default..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    return Ensure-VersionSchema -Version $obj
}

Write-Host "=== Kydras Enterprise CLI Updater ==="
Write-Host "Version file: $VersionFile"

$version = Get-VersionObject

$oldVersionString = "{0}.{1}.{2} (build {3})" -f $version.major, $version.minor, $version.patch, $version.build
Write-Host "[*] Current version: $oldVersionString"

switch ($Bump) {
    'Major' {
        $version.major++
        $version.minor = 0
        $version.patch = 0
        $version.build = 0
    }
    'Minor' {
        $version.minor++
        $version.patch = 0
        $version.build = 0
    }
    'Patch' {
        $version.patch++
        $version.build = 0
    }
    'Build' {
        $version.build++
    }
}

# Always bump build at least once per run if we didn't explicitly bump Build
if ($Bump -ne 'Build') {
    $version.build++
}

# Ensure lastUpdated exists and set it
if ($version.PSObject.Properties.Match('lastUpdated')) {
    $version.lastUpdated = (Get-Date).ToString('o')
}
else {
    Add-Member -InputObject $version -MemberType NoteProperty -Name 'lastUpdated' -Value (Get-Date).ToString('o')
}

$newVersionString = "{0}.{1}.{2} (build {3})" -f $version.major, $version.minor, $version.patch, $version.build
Write-Host "[OK] New version: $newVersionString" -ForegroundColor Green

# Write JSON atomically
$tempFile = "$VersionFile.tmp"

$version | ConvertTo-Json -Depth 4 | Set-Content -Path $tempFile -Encoding UTF8
Move-Item -Path $tempFile -Destination $VersionFile -Force

Write-Host "[OK] version.json updated." -ForegroundColor Green
Write-Host "[*] Message: $Message"
'@

# --- New script content: Kydras-RepoManager.ps1 ------------------------------

$repoManagerScript = @'
<# 
    Kydras-RepoManager.ps1 (v6-fixed)

    Purpose:
      - Central menu for managing all Kydras repos
      - Integrates:
          1) Clone-All-KydrasRepos.ps1
          2) Run-KydrasFullPipeline.ps1
          3) Add single repo to managed list
          4) Bulk add repos from file

    Conventions:
      - Root repos folder: K:\Kydras\Repos
      - Logs:             K:\Kydras\Logs\RepoManager
      - Config:           <scriptDir>\config\managed-repos.txt
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Paths -------------------------------------------------------------------

$ScriptDir  = Split-Path -Parent $PSCommandPath
$BaseDir    = $ScriptDir
$ReposRoot  = 'K:\Kydras\Repos'
$LogsRoot   = 'K:\Kydras\Logs\RepoManager'
$ConfigDir  = Join-Path $BaseDir 'config'
$RepoList   = Join-Path $ConfigDir 'managed-repos.txt'

$CloneScript    = Join-Path $BaseDir 'Clone-All-KydrasRepos.ps1'
$PipelineScript = Join-Path $BaseDir 'Run-KydrasFullPipeline.ps1'

foreach ($dir in @($ReposRoot, $LogsRoot, $ConfigDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

if (-not (Test-Path $RepoList)) {
    New-Item -ItemType File -Path $RepoList -Force | Out-Null
}

# --- Logging -----------------------------------------------------------------

$SessionLog = Join-Path $LogsRoot ("RepoManager_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $SessionLog -Append
}

Write-Log "=== Kydras RepoManager started ==="

# --- Helpers -----------------------------------------------------------------

function Show-RepoList {
    $repos = Get-Content $RepoList | Where-Object { $_.Trim() -ne '' }
    if (-not $repos) {
        Write-Host "No managed repos yet." -ForegroundColor Yellow
        return
    }

    Write-Host "`nManaged Repos:"
    $i = 1
    foreach ($r in $repos) {
        Write-Host ("  {0}. {1}" -f $i, $r)
        $i++
    }
    Write-Host ""
}

function Add-SingleRepo {
    Write-Host "`nEnter a repo identifier."
    Write-Host "This can be:"
    Write-Host "  - a local directory name under $ReposRoot"
    Write-Host "  - a full local path"
    Write-Host "  - a GitHub URL (https://github.com/...)"
    $inputRepo = Read-Host "Repo"

    if ([string]::IsNullOrWhiteSpace($inputRepo)) {
        Write-Host "[!] Empty input, cancelled." -ForegroundColor Yellow
        return
    }

    $inputRepo = $inputRepo.Trim()

    $existing = Get-Content $RepoList | Where-Object { $_.Trim() -ne '' }
    if ($existing -contains $inputRepo) {
        Write-Host "[!] Repo already in list." -ForegroundColor Yellow
        return
    }

    Add-Content -Path $RepoList -Value $inputRepo
    Write-Host "[OK] Added repo: $inputRepo" -ForegroundColor Green
    Write-Log "Added repo: $inputRepo"
}

function Add-BulkRepos {
    $path = Read-Host "Path to text file containing repo entries (one per line)"
    if (-not (Test-Path $path)) {
        Write-Host "[!] File not found: $path" -ForegroundColor Red
        return
    }

    $newItems = Get-Content $path | Where-Object { $_.Trim() -ne '' }
    if (-not $newItems) {
        Write-Host "[!] No entries found in file." -ForegroundColor Yellow
        return
    }

    $existing = @()
    if (Test-Path $RepoList) {
        $existing = Get-Content $RepoList | Where-Object { $_.Trim() -ne '' }
    }

    $toAdd = @()
    foreach ($item in $newItems) {
        $trim = $item.Trim()
        if (-not ($existing -contains $trim)) {
            $toAdd += $trim
        }
    }

    if (-not $toAdd) {
        Write-Host "[!] All entries already present, nothing to add." -ForegroundColor Yellow
        return
    }

    Add-Content -Path $RepoList -Value $toAdd
    Write-Host "[OK] Added {0} new repos from bulk file." -f $toAdd.Count -ForegroundColor Green
    Write-Log "Bulk added $($toAdd.Count) repos from $path"
}

function Run-CloneAll {
    if (-not (Test-Path $CloneScript)) {
        Write-Host "[!] Clone-All-KydrasRepos.ps1 not found at: $CloneScript" -ForegroundColor Red
        Write-Log "Clone script missing at $CloneScript"
        return
    }

    Write-Host "`n[RUN] Clone-All-KydrasRepos.ps1`n" -ForegroundColor Cyan
    Write-Log "Invoking clone script: $CloneScript"
    & $CloneScript
    Write-Host "`n[OK] Clone-All completed (see its own log for details)." -ForegroundColor Green
}

function Run-FullPipeline {
    if (-not (Test-Path $PipelineScript)) {
        Write-Host "[!] Run-KydrasFullPipeline.ps1 not found at: $PipelineScript" -ForegroundColor Red
        Write-Log "Pipeline script missing at $PipelineScript"
        return
    }

    Write-Host "`n[RUN] Run-KydrasFullPipeline.ps1`n" -ForegroundColor Cyan
    Write-Log "Invoking pipeline script: $PipelineScript"

    & $PipelineScript -RepoListPath $RepoList

    Write-Host "`n[OK] Full pipeline completed (see FullPipeline logs)." -ForegroundColor Green
}

# --- Menu Loop ---------------------------------------------------------------

while ($true) {
    Write-Host ""
    Write-Host "=== Kydras RepoManager ===" -ForegroundColor Cyan
    Write-Host "Repos root : $ReposRoot"
    Write-Host "Config     : $RepoList"
    Write-Host "Log        : $SessionLog"
    Write-Host ""
    Show-RepoList
    Write-Host "  [1] Clone all Kydras repos"
    Write-Host "  [2] Run full pipeline on managed repos"
    Write-Host "  [3] Add single repo to managed list"
    Write-Host "  [4] Bulk add repos from file"
    Write-Host "  [Q] Quit"
    Write-Host ""

    $choice = Read-Host "Select an option"

    switch ($choice.ToUpper()) {
        '1' { Run-CloneAll }
        '2' { Run-FullPipeline }
        '3' { Add-SingleRepo }
        '4' { Add-BulkRepos }
        'Q' { break }
        default {
            Write-Host "[!] Invalid choice, try again." -ForegroundColor Yellow
        }
    }
}

Write-Log "Kydras RepoManager exited."
Write-Host "`nExiting RepoManager. Goodbye.`n"
'@

# --- New script content: Run-KydrasFullPipeline.ps1 --------------------------

$pipelineScript = @'
<# 
    Run-KydrasFullPipeline.ps1 (v3-minimal)

    Purpose:
      - Iterate managed repos and run a simple pipeline:
          * Resolve repo path
          * If .git exists: run basic git commands
          * If Kydras-RepoBootstrap.ps1 exists: run it
      - Log everything to K:\Kydras\Logs\FullPipeline

    Default repo list:
      - <scriptDir>\config\managed-repos.txt
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoListPath
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$BaseDir   = $ScriptDir

if (-not $RepoListPath) {
    $RepoListPath = Join-Path $BaseDir 'config\managed-repos.txt'
}

$ReposRoot = 'K:\Kydras\Repos'
$LogsRoot  = 'K:\Kydras\Logs\FullPipeline'

foreach ($dir in @($ReposRoot, $LogsRoot)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$RunLog = Join-Path $LogsRoot ("Run-KydrasFullPipeline_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $RunLog -Append
}

Write-Log "=== Run-KydrasFullPipeline started ==="
Write-Log "Repo list: $RepoListPath"

if (-not (Test-Path $RepoListPath)) {
    Write-Log "Repo list file not found. Aborting."
    throw "Repo list not found: $RepoListPath"
}

$repos = Get-Content $RepoListPath | Where-Object { $_.Trim() -ne '' }
if (-not $repos) {
    Write-Log "Repo list is empty. Nothing to do."
    Write-Host "[!] Repo list is empty: $RepoListPath" -ForegroundColor Yellow
    return
}

$originalLocation = Get-Location

foreach ($entry in $repos) {
    $e = $entry.Trim()
    if ([string]::IsNullOrWhiteSpace($e)) { continue }

    # Determine repo directory
    $repoDir = $null

    if (Test-Path $e) {
        # Direct path
        $repoDir = (Resolve-Path $e).Path
    }
    elseif ($e -like 'https://github.com/*/*') {
        # GitHub URL -> folder name under ReposRoot
        $parts = $e.Split('/')
        $user  = $parts[-2]
        $name  = $parts[-1]
        $repoDir = Join-Path $ReposRoot $name
    }
    else {
        # Assume it's a folder name under ReposRoot
        $repoDir = Join-Path $ReposRoot $e
    }

    Write-Log "------------------------------------------------------------"
    Write-Log "Repo entry: $e"
    Write-Log "Resolved dir: $repoDir"

    if (-not (Test-Path $repoDir)) {
        Write-Log "Repo directory does not exist, skipping."
        continue
    }

    try {
        Set-Location $repoDir

        # Phase 1: basic git info
        if (Test-Path (Join-Path $repoDir '.git')) {
            Write-Log "Git repository detected. Running 'git status'."
            try {
                git status 2>&1 | ForEach-Object { Write-Log "git> $_" }
            }
            catch {
                Write-Log "git status failed: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "No .git directory found (non-git repo or missing)."
        }

        # Phase 2: optional bootstrap script
        $bootstrap = Join-Path $repoDir 'Kydras-RepoBootstrap.ps1'
        if (Test-Path $bootstrap) {
            Write-Log "Found Kydras-RepoBootstrap.ps1, executing..."
            try {
                & $bootstrap 2>&1 | ForEach-Object { Write-Log "bootstrap> $_" }
                Write-Log "Bootstrap completed."
            }
            catch {
                Write-Log "Bootstrap failed: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "No Kydras-RepoBootstrap.ps1 found, skipping bootstrap phase."
        }
    }
    finally {
        Set-Location $originalLocation
    }
}

Write-Log "=== Run-KydrasFullPipeline completed ==="
Write-Host "[OK] Full pipeline run complete. Log: $RunLog" -ForegroundColor Green
'@

# --- Write new scripts -------------------------------------------------------

Write-Host "[*] Writing updated scripts into $AppsDir"

Set-Content -Path (Join-Path $AppsDir 'Update-KydrasEnterpriseCLI.ps1') -Value $updateScript -Encoding UTF8
Set-Content -Path (Join-Path $AppsDir 'Kydras-RepoManager.ps1')       -Value $repoManagerScript -Encoding UTF8
Set-Content -Path (Join-Path $AppsDir 'Run-KydrasFullPipeline.ps1')   -Value $pipelineScript -Encoding UTF8

Write-Host "[OK] Scripts updated successfully." -ForegroundColor Green
Write-Host "Backup of previous scripts: $BackupDir"
Write-Host "You can now run:"
Write-Host "  pwsh -ExecutionPolicy Bypass -File `"$($AppsDir)\Update-KydrasEnterpriseCLI.ps1`" -Bump Patch -Message `"test release`""
Write-Host "  pwsh -ExecutionPolicy Bypass -File `"$($AppsDir)\Kydras-RepoManager.ps1`""
