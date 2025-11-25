#!/usr/bin/env pwsh
<#
    Kydras-RepoSystem-Upgrade-v3.ps1

    Upgrades the Kydras Repo tooling to v3:

    - Adds/updates:
        * Kydras-RepoIntegrityScan.ps1
        * Kydras-RepoAutoHeal.ps1
        * Kydras-RepoManager.ps1  (menu: 1–4 + Q)
        * Run-KydrasFullPipeline.ps1 (v3, with scan & auto-heal steps)
        * Kydras-RepoManagerGUI.ps1 (WinForms launcher)

    - Backs up any existing versions under:
        <BaseDir>\_backup_RepoSystem_v3_<timestamp>
#>

[CmdletBinding()]
param(
    [string]$BaseDir  = "K:\Kydras\Apps\CLI",
    [string]$ReposDir = "K:\Kydras\Repos"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Kydras-RepoSystem-Upgrade-v3.ps1 ===" -ForegroundColor Cyan
Write-Host ("BaseDir : {0}" -f $BaseDir) -ForegroundColor Yellow
Write-Host ("ReposDir: {0}" -f $ReposDir) -ForegroundColor Yellow

if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir   = Join-Path $BaseDir ("_backup_RepoSystem_v3_" + $timestamp)
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# Target files
$RepoMgrPath      = Join-Path $BaseDir "Kydras-RepoManager.ps1"
$PipelinePath     = Join-Path $BaseDir "Run-KydrasFullPipeline.ps1"
$ScanPath         = Join-Path $BaseDir "Kydras-RepoIntegrityScan.ps1"
$HealPath         = Join-Path $BaseDir "Kydras-RepoAutoHeal.ps1"
$GuiPath          = Join-Path $BaseDir "Kydras-RepoManagerGUI.ps1"

# ---------- Backup existing files ----------
$targets = @($RepoMgrPath, $PipelinePath, $ScanPath, $HealPath, $GuiPath)
foreach ($t in $targets) {
    if (Test-Path $t) {
        Write-Host ("Backing up: {0}" -f $t) -ForegroundColor Yellow
        Copy-Item $t -Destination $BackupDir -Force
    }
}

# ---------- Script: Kydras-RepoIntegrityScan.ps1 ----------
$scanContent = @"
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
    [string]$Root = "$ReposDir"
)

\$ErrorActionPreference = "Stop"

if (\$PSCommandPath) {
    \$ScriptDir = Split-Path -Parent \$PSCommandPath
} else {
    \$ScriptDir = (Get-Location).Path
}

\$LogDir = Join-Path \$ScriptDir "_logs"
if (-not (Test-Path \$LogDir)) {
    New-Item -ItemType Directory -Path \$LogDir -Force | Out-Null
}

\$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
\$LogFile   = Join-Path \$LogDir ("RepoStatus_" + \$Timestamp + ".log")

function Log {
    param([string]\$Msg)
    \$line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), \$Msg
    \$line | Out-File -FilePath \$LogFile -Append
    Write-Host \$line
}

Log "=== Kydras Repo Integrity Scan starting ==="
Log ("Root directory: {0}" -f \$Root)

if (-not (Test-Path \$Root)) {
    Log "[ERROR] Root directory not found!"
    exit 1
}

\$repos = Get-ChildItem \$Root -Directory
if (-not \$repos -or \$repos.Count -eq 0) {
    Log "[WARN] No repositories found."
    exit 0
}

foreach (\$r in \$repos) {
    Log "----"
    Log ("Scanning repo: {0}" -f \$r.Name)
    \$path = \$r.FullName

    \$gitPath = Join-Path \$path ".git"
    if (-not (Test-Path \$gitPath)) {
        Log "[ERROR] Missing .git folder → NOT a valid repo"
        continue
    }

    # Remote
    \$remote = git -C \$path remote get-url origin 2>\$null
    if (-not \$remote) {
        Log "[WARN] No origin remote configured"
    } else {
        Log ("Remote: {0}" -f \$remote)
    }

    # Branch
    \$branch = git -C \$path rev-parse --abbrev-ref HEAD 2>\$null
    if (\$branch -eq "HEAD") {
        Log "[WARN] Detached HEAD state"
    } elseif (\$branch) {
        Log ("Branch: {0}" -f \$branch)
    } else {
        Log "[WARN] Unable to determine branch"
    }

    # Uncommitted changes
    \$dirty = git -C \$path status --porcelain
    if (\$dirty) {
        Log "[WARN] Repo has uncommitted changes"
    } else {
        Log "[OK] Working tree clean"
    }

    # Fetch check
    try {
        git -C \$path fetch --dry-run 2>&1 | Out-Null
        Log "[OK] Git fetch successful"
    } catch {
        Log "[ERROR] Git fetch failed"
    }
}

Log "=== Scan Complete ==="
Log ("Log saved at: {0}" -f \$LogFile)

Write-Host ""
Write-Host "Scan complete. Log file:" -ForegroundColor Green
Write-Host \$LogFile
"@

# ---------- Script: Kydras-RepoAutoHeal.ps1 ----------
$healContent = @"
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
    [string]$Root = "$ReposDir",
    [switch]$ForceReset
)

\$ErrorActionPreference = "Stop"

Write-Host "=== Kydras Repo Auto-Heal ===" -ForegroundColor Cyan
Write-Host ("Root: {0}" -f \$Root) -ForegroundColor Yellow

if (-not (Test-Path \$Root)) {
    Write-Host "[ERROR] Root directory not found." -ForegroundColor Red
    exit 1
}

\$repos = Get-ChildItem \$Root -Directory
if (-not \$repos -or \$repos.Count -eq 0) {
    Write-Host "[WARN] No repositories found." -ForegroundColor DarkYellow
    exit 0
}

foreach (\$r in \$repos) {
    \$name = \$r.Name
    \$path = \$r.FullName

    Write-Host "----"
    Write-Host "Healing repo: \$name" -ForegroundColor Yellow

    if (-not (Test-Path (Join-Path \$path ".git"))) {
        Write-Host "[ERROR] Not a git repo → skipping" -ForegroundColor Red
        continue
    }

    # Branch
    \$branch = git -C \$path rev-parse --abbrev-ref HEAD 2>\$null
    if (-not \$branch) {
        Write-Host "[WARN] Unable to determine current branch." -ForegroundColor DarkYellow
    } elseif (\$branch -eq "HEAD") {
        Write-Host "[FIX] Detached HEAD → attempting 'main' then 'master'" -ForegroundColor Cyan
        git -C \$path checkout main 2>\$null
        \$branch = git -C \$path rev-parse --abbrev-ref HEAD 2>\$null
        if (\$branch -eq "HEAD") {
            git -C \$path checkout master 2>\$null
            \$branch = git -C \$path rev-parse --abbrev-ref HEAD 2>\$null
        }
    }

    # Remote
    \$remote = git -C \$path remote get-url origin 2>\$null
    if (-not \$remote) {
        Write-Host "[FIX] No origin remote → guessing GitHub URL." -ForegroundColor Cyan
        \$guess = "https://github.com/Kydras8/\$name.git"
        git -C \$path remote add origin \$guess
        Write-Host ("Added origin: {0}" -f \$guess) -ForegroundColor Green
        \$remote = \$guess
    } else {
        Write-Host ("Origin: {0}" -f \$remote) -ForegroundColor Gray
    }

    # Fetch
    try {
        git -C \$path fetch --all
        Write-Host "[OK] Fetch successful" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Fetch failed, attempting remote repair..." -ForegroundColor DarkYellow
        if (-not \$remote) {
            \$remote = "https://github.com/Kydras8/\$name.git"
        }
        git -C \$path remote remove origin 2>\$null
        git -C \$path remote add origin \$remote
        git -C \$path fetch --all
    }

    if (\$ForceReset -and \$branch -and \$branch -ne "HEAD") {
        Write-Host ("[RESET] Hard resetting to origin/{0}" -f \$branch) -ForegroundColor Red
        git -C \$path reset --hard ("origin/" + \$branch)
    }

    Write-Host "[DONE] Repo healed: \$name" -ForegroundColor Green
}
"@

# ---------- Script: Kydras-RepoManager.ps1 ----------
$repoMgrContent = @"
#!/usr/bin/env pwsh
<#
    Kydras-RepoManager.ps1

    Menu:
      [1] Clone / Update ALL repos
      [2] Run FULL Kydras pipeline
      [3] Scan repo health
      [4] Auto-heal repos
      [Q] Quit
#>

\$ErrorActionPreference = "Stop"

if (\$PSCommandPath) {
    \$ScriptDir = Split-Path -Parent \$PSCommandPath
} else {
    \$ScriptDir = (Get-Location).Path
}

\$CloneScript    = Join-Path \$ScriptDir "Clone-All-KydrasRepos.ps1"
\$PipelineScript = Join-Path \$ScriptDir "Run-KydrasFullPipeline.ps1"
\$ScanScript     = Join-Path \$ScriptDir "Kydras-RepoIntegrityScan.ps1"
\$HealScript     = Join-Path \$ScriptDir "Kydras-RepoAutoHeal.ps1"

function Invoke-CloneAll {
    if (-not (Test-Path \$CloneScript)) {
        Write-Host "Missing Clone-All-KydrasRepos.ps1 at: \$CloneScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Clone-All-KydrasRepos.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File \$CloneScript
}

function Invoke-FullPipeline {
    if (-not (Test-Path \$PipelineScript)) {
        Write-Host "Missing Run-KydrasFullPipeline.ps1 at: \$PipelineScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Run-KydrasFullPipeline.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File \$PipelineScript
}

function Invoke-Scan {
    if (-not (Test-Path \$ScanScript)) {
        Write-Host "Missing Kydras-RepoIntegrityScan.ps1 at: \$ScanScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Kydras-RepoIntegrityScan.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File \$ScanScript
}

function Invoke-Heal {
    if (-not (Test-Path \$HealScript)) {
        Write-Host "Missing Kydras-RepoAutoHeal.ps1 at: \$HealScript" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ">>> Running Kydras-RepoAutoHeal.ps1 ..." -ForegroundColor Cyan
    pwsh -ExecutionPolicy Bypass -File \$HealScript
}

while (\$true) {
    Write-Host ""
    Write-Host "===== Kydras Repo Manager =====" -ForegroundColor Green
    Write-Host "[1] Clone / Update ALL repos"
    Write-Host "[2] Run FULL Kydras pipeline"
    Write-Host "[3] Scan repo health"
    Write-Host "[4] Auto-heal repos"
    Write-Host "[Q] Quit"
    Write-Host "==============================="

    \$choice = Read-Host "Select option"

    switch (\$choice.ToUpper()) {
        "1" { Invoke-CloneAll }
        "2" { Invoke-FullPipeline }
        "3" { Invoke-Scan }
        "4" { Invoke-Heal }
        "Q" { break }
        default {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    }
}

Write-Host "Exiting Kydras-RepoManager." -ForegroundColor Cyan
"@

# ---------- Script: Run-KydrasFullPipeline.ps1 (v3) ----------
$pipelineContent = @"
#!/usr/bin/env pwsh
<#
    Run-KydrasFullPipeline.ps1 (v3)

    Steps:
      1) Clone / Update ALL repos
      2) Kydras-RepoBootstrap.ps1 (optional)
      3) Build-KydrasRepoSync.ps1 (optional)
      4) Kydras-RepoIntegrityScan.ps1 (optional)
      5) Kydras-RepoAutoHeal.ps1 (optional)
#>

\$ErrorActionPreference = "Stop"

if (\$PSCommandPath) {
    \$ScriptDir = Split-Path -Parent \$PSCommandPath
} else {
    \$ScriptDir = (Get-Location).Path
}

\$LogDir = Join-Path \$ScriptDir "_logs"
if (-not (Test-Path \$LogDir)) {
    New-Item -ItemType Directory -Path \$LogDir -Force | Out-Null
}

\$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
\$LogFile   = Join-Path \$LogDir ("Run-KydrasFullPipeline_" + \$Timestamp + ".log")

function Write-PipelineLog {
    param([string]\$Message, [string]\$Level = "INFO")

    \$line = "{0} [{1}] {2}" -f (Get-Date -Format "u"), \$Level, \$Message
    \$line | Out-File -FilePath \$LogFile -Append -Encoding UTF8
    Write-Host \$line
}

function Invoke-Step {
    param(
        [string]\$Name,
        [ScriptBlock]\$Action
    )

    Write-PipelineLog "=== STEP: \$Name ==="
    try {
        & \$Action
        Write-PipelineLog "STEP OK: \$Name"
    } catch {
        Write-PipelineLog "STEP FAILED: \$Name - \$($_)" "ERROR"
    }
}

\$CloneScript     = Join-Path \$ScriptDir "Clone-All-KydrasRepos.ps1"
\$BootstrapScript = Join-Path \$ScriptDir "Kydras-RepoBootstrap.ps1"
\$BuildSync       = Join-Path \$ScriptDir "Build-KydrasRepoSync.ps1"
\$ScanScript      = Join-Path \$ScriptDir "Kydras-RepoIntegrityScan.ps1"
\$HealScript      = Join-Path \$ScriptDir "Kydras-RepoAutoHeal.ps1"
\$FullPipeline    = Join-Path \$ScriptDir "KydrasFullPipeline.ps1"

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 v3 START ====="

Invoke-Step "Clone / Update ALL repos" {
    if (-not (Test-Path \$CloneScript)) {
        throw "Clone-All-KydrasRepos.ps1 not found at \$CloneScript"
    }
    pwsh -ExecutionPolicy Bypass -File \$CloneScript
}

Invoke-Step "Kydras-RepoBootstrap.ps1 (optional)" {
    if (Test-Path \$BootstrapScript) {
        pwsh -ExecutionPolicy Bypass -File \$BootstrapScript
    } else {
        Write-PipelineLog "Kydras-RepoBootstrap.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "Build-KydrasRepoSync.ps1 (optional)" {
    if (Test-Path \$BuildSync) {
        pwsh -ExecutionPolicy Bypass -File \$BuildSync
    } else {
        Write-PipelineLog "Build-KydrasRepoSync.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "Kydras-RepoIntegrityScan.ps1 (optional)" {
    if (Test-Path \$ScanScript) {
        pwsh -ExecutionPolicy Bypass -File \$ScanScript
    } else {
        Write-PipelineLog "Kydras-RepoIntegrityScan.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "Kydras-RepoAutoHeal.ps1 (optional)" {
    if (Test-Path \$HealScript) {
        pwsh -ExecutionPolicy Bypass -File \$HealScript
    } else {
        Write-PipelineLog "Kydras-RepoAutoHeal.ps1 not found, skipping." "WARN"
    }
}

Invoke-Step "KydrasFullPipeline.ps1 (optional)" {
    if (Test-Path \$FullPipeline) {
        pwsh -ExecutionPolicy Bypass -File \$FullPipeline
    } else {
        Write-PipelineLog "KydrasFullPipeline.ps1 not found, skipping." "WARN"
    }
}

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 v3 COMPLETE ====="
Write-Host ""
Write-Host "Run-KydrasFullPipeline v3 complete." -ForegroundColor Green
Write-Host ("Log: {0}" -f \$LogFile) -ForegroundColor Yellow
"@

# ---------- Script: Kydras-RepoManagerGUI.ps1 ----------
$guiContent = @"
#!/usr/bin/env pwsh
<#
    Kydras-RepoManagerGUI.ps1
    - Simple WinForms GUI wrapper for Kydras Repo Manager actions
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (\$PSCommandPath) {
    \$ScriptDir = Split-Path -Parent \$PSCommandPath
} else {
    \$ScriptDir = (Get-Location).Path
}

\$CloneScript    = Join-Path \$ScriptDir "Clone-All-KydrasRepos.ps1"
\$PipelineScript = Join-Path \$ScriptDir "Run-KydrasFullPipeline.ps1"
\$ScanScript     = Join-Path \$ScriptDir "Kydras-RepoIntegrityScan.ps1"
\$HealScript     = Join-Path \$ScriptDir "Kydras-RepoAutoHeal.ps1"

function Start-ExternalScript([string]\$path) {
    if (-not (Test-Path \$path)) {
        [System.Windows.Forms.MessageBox]::Show("Script not found:`n`n\$path","Missing Script",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"\$path`""
}

\$form              = New-Object System.Windows.Forms.Form
\$form.Text         = "Kydras Repo Manager"
\$form.Size         = New-Object System.Drawing.Size(420,260)
\$form.StartPosition= "CenterScreen"

\$font = New-Object System.Drawing.Font("Segoe UI",10)

\$btnClone          = New-Object System.Windows.Forms.Button
\$btnClone.Text     = "Clone / Update All Repos"
\$btnClone.Size     = New-Object System.Drawing.Size(360,35)
\$btnClone.Location = New-Object System.Drawing.Point(20,20)
\$btnClone.Font     = \$font
\$btnClone.Add_Click({ Start-ExternalScript \$CloneScript })

\$btnPipeline          = New-Object System.Windows.Forms.Button
\$btnPipeline.Text     = "Run Full Pipeline"
\$btnPipeline.Size     = New-Object System.Drawing.Size(360,35)
\$btnPipeline.Location = New-Object System.Drawing.Point(20,65)
\$btnPipeline.Font     = \$font
\$btnPipeline.Add_Click({ Start-ExternalScript \$PipelineScript })

\$btnScan          = New-Object System.Windows.Forms.Button
\$btnScan.Text     = "Scan Repo Health"
\$btnScan.Size     = New-Object System.Drawing.Size(360,35)
\$btnScan.Location = New-Object System.Drawing.Point(20,110)
\$btnScan.Font     = \$font
\$btnScan.Add_Click({ Start-ExternalScript \$ScanScript })

\$btnHeal          = New-Object System.Windows.Forms.Button
\$btnHeal.Text     = "Auto-Heal Repos"
\$btnHeal.Size     = New-Object System.Drawing.Size(360,35)
\$btnHeal.Location = New-Object System.Drawing.Point(20,155)
\$btnHeal.Font     = \$font
\$btnHeal.Add_Click({ Start-ExternalScript \$HealScript })

\$btnClose          = New-Object System.Windows.Forms.Button
\$btnClose.Text     = "Close"
\$btnClose.Size     = New-Object System.Drawing.Size(360,30)
\$btnClose.Location = New-Object System.Drawing.Point(20,200)
\$btnClose.Font     = \$font
\$btnClose.Add_Click({ \$form.Close() })

\$form.Controls.AddRange(@(\$btnClone,\$btnPipeline,\$btnScan,\$btnHeal,\$btnClose))

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run(\$form)
"@

# ---------- Write all files ----------
Write-Host "Writing Kydras-RepoIntegrityScan.ps1 -> $ScanPath" -ForegroundColor Yellow
Set-Content -Path $ScanPath -Value $scanContent -Encoding UTF8

Write-Host "Writing Kydras-RepoAutoHeal.ps1 -> $HealPath" -ForegroundColor Yellow
Set-Content -Path $HealPath -Value $healContent -Encoding UTF8

Write-Host "Writing Kydras-RepoManager.ps1 -> $RepoMgrPath" -ForegroundColor Yellow
Set-Content -Path $RepoMgrPath -Value $repoMgrContent -Encoding UTF8

Write-Host "Writing Run-KydrasFullPipeline.ps1 (v3) -> $PipelinePath" -ForegroundColor Yellow
Set-Content -Path $PipelinePath -Value $pipelineContent -Encoding UTF8

Write-Host "Writing Kydras-RepoManagerGUI.ps1 -> $GuiPath" -ForegroundColor Yellow
Set-Content -Path $GuiPath -Value $guiContent -Encoding UTF8

Write-Host ""
Write-Host "[✓] Kydras-RepoSystem-Upgrade-v3 complete." -ForegroundColor Green
Write-Host ("Backups stored in: {0}" -f $BackupDir) -ForegroundColor Green
