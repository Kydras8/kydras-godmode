#!/usr/bin/env pwsh
<#
Kydras-Enterprise-Upgrade.ps1

One-shot upgrade that enables:

A) Nightly full pipeline (Task Scheduler)
B) Live GUI status bar with color
C) Toast notifications via BurntToast
D) Advanced repo polish (CODEOWNERS, CONTRIBUTING, templates)
E) Auto-updater build script
F) Version stamping
G) Enterprise launcher EXE

Run from:
  K:\Kydras\Apps\CLI

Usage:
  pwsh -ExecutionPolicy Bypass -File .\Kydras-Enterprise-Upgrade.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$AppsDir   = "K:\Kydras\Apps\CLI"
$RepoRoot  = "K:\Kydras\Repos"
$Version   = "1.0.0"
$NowStamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if (-not (Test-Path $AppsDir)) { throw "Apps directory not found: $AppsDir" }
if (-not (Test-Path $RepoRoot)) {
    Write-Host "Creating repo root at $RepoRoot" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $RepoRoot -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $AppsDir "backup-enterprise-$timestamp"
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Write-Host "Backup directory: $BackupDir" -ForegroundColor Cyan

function Backup-IfExists {
    param(
        [string]$Path
    )
    if (Test-Path $Path) {
        $name = Split-Path $Path -Leaf
        $dest = Join-Path $BackupDir $name
        Write-Host "Backing up $name -> $dest" -ForegroundColor Green
        Move-Item -Path $Path -Destination $dest -Force
    }
}

# Paths
$RepoMgrPath     = Join-Path $RepoRoot "kydras-repo-manager-v4.ps1"
$FullPipeline    = Join-Path $AppsDir "Run-KydrasFullPipeline.ps1"
$GuiPath         = Join-Path $AppsDir "kydras-cli-gui.ps1"
$BuildBundlePath = Join-Path $AppsDir "Build-KydrasEnterpriseBundle.ps1"
$LauncherPath    = Join-Path $AppsDir "Kydras-Enterprise-Launcher.ps1"
$VersionFile     = Join-Path $AppsDir "Kydras-Tools-Version.txt"

Backup-IfExists $RepoMgrPath
Backup-IfExists $FullPipeline
Backup-IfExists $GuiPath
Backup-IfExists $BuildBundlePath
Backup-IfExists $LauncherPath
Backup-IfExists $VersionFile

# ==========================
# D) Advanced Repo Manager
# ==========================

$repoManagerContent = @'
#!/usr/bin/env pwsh
<#
kydras-repo-manager-v4.ps1
Kydras Repo Manager v4 — HTTPS + Advanced Polish

Modes:
  sync   — clone/update via HTTPS cloneUrl (gh repo list)
  polish — LICENSE, FUNDING, README header, SECURITY, CODEOWNERS,
            CONTRIBUTING, issue/PR templates
  push   — commit/push changes

Version: 1.0.0
#>

[CmdletBinding()]
param(
    [ValidateSet("sync","polish","push")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$Root  = "K:\Kydras\Repos"
$Log   = Join-Path $Root "_repo-manager-log.txt"
$Users = @("Kydras8", "Kydras-Systems-Inc")

# Branding content
$ApacheLicense = @(
"Apache License",
"Version 2.0, January 2004",
"http://www.apache.org/licenses/",
"",
"TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION ...",
"",
"Copyright (c) $(Get-Date -Format yyyy)",
"Kydras Systems Inc."
) -join "`r`n"

$ReadmeHeader = @(
"<!-- Kydras Repo Header -->",
'<p align="center">',
"  <strong>Kydras Systems Inc.</strong><br/>",
"  <em>Nothing is off limits.</em>",
"</p>",
"",
"---",
""
) -join "`r`n"

$FundingYaml = @(
"github: [Kydras8]",
"custom:",
"  - https://www.buymeacoffee.com/kydras"
) -join "`r`n"

$SecurityMd = @(
"# Security Policy",
"",
"Report issues to: security@kydras-systems-inc.com",
"",
"Please include steps to reproduce and impact assessment where possible."
) -join "`r`n"

$Codeowners = @(
"*   @Kydras8"
) -join "`r`n"

$Contributing = @(
"# Contributing",
"",
"Thank you for considering contributing to Kydras Systems Inc. projects.",
"",
"1. Fork the repo",
"2. Create a feature branch",
"3. Commit changes with clear messages",
"4. Open a Pull Request",
"",
"Follow security and coding best practices."
) -join "`r`n"

$IssueBug = @(
"---",
"name: Bug report",
"about: Create a report to help us improve",
"---",
"",
"**Describe the bug**",
"",
"**To Reproduce**",
"",
"**Expected behavior**",
"",
"**Screenshots**",
"",
"**Environment (please complete the following information):**",
"- OS:",
"- Version:",
"",
"**Additional context**"
) -join "`r`n"

$IssueFeature = @(
"---",
"name: Feature request",
"about: Suggest an idea for this project",
"---",
"",
"**Is your feature request related to a problem?**",
"",
"**Describe the solution you'd like**",
"",
"**Describe alternatives you've considered**",
"",
"**Additional context**"
) -join "`r`n"

$PrTemplate = @(
"# Pull Request",
"",
"## Description",
"",
"## Changes",
"-",
"",
"## Testing",
"-",
"",
"## Checklist",
"- [ ] Tests added/updated",
"- [ ] Docs updated (if needed)"
) -join "`r`n"

function Write-Log {
    param([string]$Message)
    $text = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $text | Out-File -FilePath $Log -Append
    Write-Host $Message
}

function Ensure-Tool {
    param([string]$Name,[string]$Cmd)
    try { Invoke-Expression $Cmd | Out-Null }
    catch {
        Write-Log "ERROR: '$Name' not found (or not in PATH)."
        throw
    }
}

function Ensure-GhAuth {
    try { gh auth status | Out-Null }
    catch {
        Write-Log "ERROR: Run 'gh auth login' (HTTPS) first."
        throw
    }
}

function Get-RepoDirectories {
    if (-not (Test-Path $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
    return Get-ChildItem -Path $Root -Directory | Where-Object { Test-Path "$($_.FullName)\.git" }
}

# -------- SYNC MODE (HTTPS) --------------

function Mode-Sync {

    Write-Log "=== MODE: SYNC (HTTPS) ==="

    Ensure-Tool "gh"  "gh --version"
    Ensure-Tool "git" "git --version"
    Ensure-GhAuth

    foreach ($u in $Users) {

        Write-Log "---- Fetching repos for '$u' ----"

        $reposJson = gh repo list $u --limit 200 --json name,cloneUrl 2>$null
        if ([string]::IsNullOrWhiteSpace($reposJson)) {
            Write-Log "No JSON returned for $u."
            continue
        }

        $repos = $reposJson | ConvertFrom-Json
        if (-not $repos) {
            Write-Log "No repos parsed for $u."
            continue
        }

        foreach ($r in $repos) {

            $name     = $r.name
            $cloneUrl = $r.cloneUrl

            if ([string]::IsNullOrWhiteSpace($name) -or
                [string]::IsNullOrWhiteSpace($cloneUrl)) {
                Write-Log "Skipping invalid repo entry."
                continue
            }

            $target = Join-Path $Root $name

            if (Test-Path $target) {
                Write-Log "Pulling updates for: $name"
                try { git -C $target pull | Out-File $Log -Append }
                catch { Write-Log "ERROR pulling $name : $_" }
            }
            else {
                Write-Log "Cloning new repo via HTTPS: $name"
                try { git clone $cloneUrl $target | Out-File $Log -Append }
                catch { Write-Log "ERROR cloning $name : $_" }
            }
        }

        Write-Log "---- Finished syncing '$u' ----"
    }

    Write-Log "SYNC complete (HTTPS)."
}

# -------- POLISH MODE ---------------------

function Mode-Polish {
    Write-Log "=== MODE: POLISH (Advanced) ==="
    $repos = Get-RepoDirectories

    foreach ($repo in $repos) {
        $name = $repo.Name
        $path = $repo.FullName
        Write-Log "Polishing: $name"

        # LICENSE
        $license = Join-Path $path "LICENSE"
        if (-not (Test-Path $license)) { $ApacheLicense | Out-File $license -Encoding UTF8 }

        # .github dir
        $ghDir = Join-Path $path ".github"
        if (-not (Test-Path $ghDir)) { New-Item -ItemType Directory -Path $ghDir -Force | Out-Null }

        # FUNDING
        $fund = Join-Path $ghDir "FUNDING.yml"
        if (-not (Test-Path $fund)) { $FundingYaml | Out-File $fund -Encoding UTF8 }

        # SECURITY
        $sec = Join-Path $ghDir "SECURITY.md"
        if (-not (Test-Path $sec)) { $SecurityMd | Out-File $sec -Encoding UTF8 }

        # CODEOWNERS
        $codeownersPath = Join-Path $ghDir "CODEOWNERS"
        if (-not (Test-Path $codeownersPath)) { $Codeowners | Out-File $codeownersPath -Encoding UTF8 }

        # CONTRIBUTING
        $contribPath = Join-Path $path "CONTRIBUTING.md"
        if (-not (Test-Path $contribPath)) { $Contributing | Out-File $contribPath -Encoding UTF8 }

        # Issue templates
        $issueDir = Join-Path $ghDir "ISSUE_TEMPLATE"
        if (-not (Test-Path $issueDir)) { New-Item -ItemType Directory -Path $issueDir -Force | Out-Null }

        $bugPath = Join-Path $issueDir "bug_report.md"
        if (-not (Test-Path $bugPath)) { $IssueBug | Out-File $bugPath -Encoding UTF8 }

        $featPath = Join-Path $issueDir "feature_request.md"
        if (-not (Test-Path $featPath)) { $IssueFeature | Out-File $featPath -Encoding UTF8 }

        # PR template
        $prPath = Join-Path $ghDir "pull_request_template.md"
        if (-not (Test-Path $prPath)) { $PrTemplate | Out-File $prPath -Encoding UTF8 }

        # README
        $readme = Join-Path $path "README.md"
        if (Test-Path $readme) {
            $content = Get-Content $readme -Raw
            if ($content -notmatch "Kydras Repo Header") {
                ($ReadmeHeader + "`r`n" + $content) | Out-File $readme -Encoding UTF8
            }
        }
        else {
            $ReadmeHeader | Out-File $readme -Encoding UTF8
        }
    }

    Write-Log "POLISH complete."
}

# -------- PUSH MODE -----------------------

function Mode-Push {
    Write-Log "=== MODE: PUSH ==="

    Ensure-Tool "git" "git --version"
    $repos = Get-RepoDirectories

    foreach ($repo in $repos) {
        $name = $repo.Name
        $path = $repo.FullName

        Write-Log "Checking changes: $name"

        try { $status = git -C $path status --porcelain }
        catch {
            Write-Log "Cannot get status for $name"
            continue
        }

        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Log "No changes in $name"
            continue
        }

        Write-Log "Committing + pushing: $name"

        try {
            git -C $path add -A       | Out-File $Log -Append
            git -C $path commit -m "[Kydras] Repo polish" | Out-File $Log -Append
            git -C $path push         | Out-File $Log -Append
        }
        catch {
            Write-Log "ERROR pushing $name : $_"
        }
    }

    Write-Log "PUSH complete."
}

"---- $(Get-Date) MODE=$Mode ----" | Out-File -FilePath $Log -Append

switch ($Mode) {
    "sync"   { Mode-Sync }
    "polish" { Mode-Polish }
    "push"   { Mode-Push }
}

Write-Host "`n[✓] Finished. Log: $Log"
'@

Set-Content -Path $RepoMgrPath -Value $repoManagerContent -Encoding UTF8
Write-Host "Updated repo manager: $RepoMgrPath" -ForegroundColor Green

# ==========================
# C) Full Pipeline + Toast
# ==========================

$pipelineContent = @'
#!/usr/bin/env pwsh
<#
Run-KydrasFullPipeline.ps1

Runs:
  1) Clone-All-KydrasRepos.ps1 (HTTPS)
  2) kydras-repo-manager-v4.ps1 sync
  3) kydras-repo-manager-v4.ps1 polish
  4) kydras-repo-manager-v4.ps1 push

Sends toast notifications if BurntToast is installed.
Logs to: K:\Kydras\Repos\_full-pipeline.log

Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot          = "K:\Kydras\Repos"
$CloneAllScript    = "K:\Kydras\Apps\CLI\Clone-All-KydrasRepos.ps1"
$RepoManagerScript = "K:\Kydras\Repos\kydras-repo-manager-v4.ps1"
$Log               = Join-Path $RepoRoot "_full-pipeline.log"

$HasToast = $false
try {
    Import-Module BurntToast -ErrorAction Stop
    $HasToast = $true
}
catch {
    $HasToast = $false
}

function Write-PipelineLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $Log -Append
    Write-Host $Message
}

function Send-Toast {
    param([string]$Title,[string]$Message)
    if (-not $HasToast) { return }
    try {
        New-BurntToastNotification -Text $Title,$Message | Out-Null
    }
    catch { }
}

Write-PipelineLog ""
Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 START ====="
Send-Toast "Kydras Pipeline" "Full pipeline started."

try {
    Write-PipelineLog "STEP 1: Clone-All (HTTPS) starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $CloneAllScript
    Write-PipelineLog "STEP 1: Clone-All completed."
}
catch {
    Write-PipelineLog "ERROR in Clone-All: $_"
    Send-Toast "Kydras Pipeline ERROR" "Clone-All step failed."
}

try {
    Write-PipelineLog "STEP 2: Repo Manager SYNC starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript sync
    Write-PipelineLog "STEP 2: Repo Manager SYNC completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager SYNC: $_"
    Send-Toast "Kydras Pipeline ERROR" "SYNC step failed."
}

try {
    Write-PipelineLog "STEP 3: Repo Manager POLISH starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript polish
    Write-PipelineLog "STEP 3: Repo Manager POLISH completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager POLISH: $_"
    Send-Toast "Kydras Pipeline ERROR" "POLISH step failed."
}

try {
    Write-PipelineLog "STEP 4: Repo Manager PUSH starting..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RepoManagerScript push
    Write-PipelineLog "STEP 4: Repo Manager PUSH completed."
}
catch {
    Write-PipelineLog "ERROR in Repo Manager PUSH: $_"
    Send-Toast "Kydras Pipeline ERROR" "PUSH step failed."
}

Write-PipelineLog "===== Run-KydrasFullPipeline.ps1 COMPLETE ====="
Send-Toast "Kydras Pipeline" "Full pipeline completed."
'@

Set-Content -Path $FullPipeline -Value $pipelineContent -Encoding UTF8
Write-Host "Updated full pipeline: $FullPipeline" -ForegroundColor Green

# ======================================
# B + E) GUI with live status + updater
# ======================================

$guiContent = @'
#!/usr/bin/env pwsh
<#
kydras-cli-gui.ps1

Kydras Repo Tools (HTTPS Engine)
 - Live status bar (auto-refresh)
 - Full pipeline button (Clone→Sync→Polish→Push)
 - Update Tools button (build bundle)

Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$RepoRoot              = "K:\Kydras\Repos"
$CloneAllScript        = "K:\Kydras\Apps\CLI\Clone-All-KydrasRepos.ps1"
$CloneUserScript       = "K:\Kydras\Apps\CLI\Clone-Kydras8Repos.ps1"
$RepoManagerScript     = "K:\Kydras\Repos\kydras-repo-manager-v4.ps1"
$FullPipelineScript    = "K:\Kydras\Apps\CLI\Run-KydrasFullPipeline.ps1"
$BuildBundleScript     = "K:\Kydras\Apps\CLI\Build-KydrasEnterpriseBundle.ps1"

$LogFileCloneAll       = Join-Path $RepoRoot "_clone-all-kydras-repos.log"
$LogFileRepoMgr        = Join-Path $RepoRoot "_repo-manager-log.txt"
$LogFilePipeline       = Join-Path $RepoRoot "_full-pipeline.log"

$LogoPath              = "K:\Kydras\Apps\CLI\kydras-logo.png"
$IconPath              = "K:\Kydras\Apps\CLI\kydras.ico"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-ErrorBox {
    param([string]$Message,[string]$Title = "Kydras Repo Tools - Error")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-InfoBox {
    param([string]$Message,[string]$Title = "Kydras Repo Tools (HTTPS Engine)")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Ensure-FileExists {
    param([string]$Path,[string]$Description)
    if (-not (Test-Path $Path)) {
        Show-ErrorBox "Missing file: $Description`n`nExpected at:`n$Path"
        return $false
    }
    return $true
}

# -------- Status Helpers --------

$script:StatusLabel = $null

function Get-LogStatus {
    param([string]$Path,[string]$Prefix)

    if (-not (Test-Path $Path)) {
        return "${Prefix}: (no runs yet)"
    }

    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
        if (-not $lines -or $lines.Count -eq 0) {
            return "${Prefix}: (log empty)"
        }

        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = $lines[$i].Trim()
            if ($line) {
                if ($line -match '^\[(?<ts>[0-9\-]{10} [0-9:]{8})\]\s*(?<msg>.+)$') {
                    $ts  = $Matches.ts
                    $msg = $Matches.msg
                    return "${Prefix}: $ts — $msg"
                }
                else {
                    return "${Prefix}: $line"
                }
            }
        }

        return "${Prefix}: (log has only blank lines)"
    }
    catch {
        return "${Prefix}: (error reading log)"
    }
}

function Refresh-StatusBar {
    if (-not $script:StatusLabel) { return }

    $cloneStatus = Get-LogStatus -Path $LogFileCloneAll -Prefix "Clone-All"
    $repoStatus  = Get-LogStatus -Path $LogFileRepoMgr  -Prefix "RepoMgr"

    $pipelineStatus = ""
    $color = [System.Drawing.Color]::FromArgb(180,180,180)

    if (Test-Path $LogFilePipeline) {
        try {
            $lines = [System.IO.File]::ReadAllLines($LogFilePipeline)
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i].Trim()
                if ($line) {
                    $pipelineStatus = $line
                    break
                }
            }
            if ($pipelineStatus -match "ERROR") {
                $color = [System.Drawing.Color]::FromArgb(200,80,80)
            }
            elseif ($pipelineStatus -match "COMPLETE") {
                $color = [System.Drawing.Color]::FromArgb(120,200,120)
            }
        }
        catch {
            $pipelineStatus = "(pipeline log error)"
        }
    }
    else {
        $pipelineStatus = "(pipeline not run yet)"
    }

    $script:StatusLabel.Text = "$cloneStatus    |    $repoStatus    |    Pipeline: $pipelineStatus"
    $script:StatusLabel.ForeColor = $color
}

# -------- Actions --------

function Run-CloneAll {
    if (-not (Ensure-FileExists $CloneAllScript "Clone-All-KydrasRepos.ps1 (HTTPS)")) { return }
    Start-Process "pwsh.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$CloneAllScript `
        -WindowStyle Minimized
    Show-InfoBox "Clone-All (user + org) started via HTTPS.`nLogs:`n$LogFileCloneAll"
    Refresh-StatusBar
}

function Run-CloneUser {
    if (-not (Ensure-FileExists $CloneUserScript "Clone-Kydras8Repos.ps1 (HTTPS)")) { return }
    Start-Process "pwsh.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$CloneUserScript `
        -WindowStyle Minimized
    Show-InfoBox "Scoped clone (Kydras8 + org) started via HTTPS."
    Refresh-StatusBar
}

function Run-RepoManagerMode {
    param([string]$Mode)
    if (-not (Ensure-FileExists $RepoManagerScript "kydras-repo-manager-v4.ps1 (HTTPS)")) { return }
    Start-Process "pwsh.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$RepoManagerScript,$Mode `
        -WindowStyle Minimized
    Show-InfoBox "Repo Manager ($Mode) started.`nLog: $LogFileRepoMgr"
    Refresh-StatusBar
}

function Run-FullPipeline {
    if (-not (Ensure-FileExists $FullPipelineScript "Run-KydrasFullPipeline.ps1")) { return }
    Start-Process "pwsh.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$FullPipelineScript `
        -WindowStyle Minimized
    Show-InfoBox "Full pipeline started (Clone→Sync→Polish→Push).`nLogs:`n$LogFilePipeline"
    Refresh-StatusBar
}

function Run-BuildBundle {
    if (-not (Ensure-FileExists $BuildBundleScript "Build-KydrasEnterpriseBundle.ps1")) { return }
    Start-Process "pwsh.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$BuildBundleScript `
        -WindowStyle Minimized
    Show-InfoBox "Kydras Enterprise Tools updater started (EXE rebuild + version bump)."
}

function Open-ReposFolder {
    if (-not (Test-Path $RepoRoot)) {
        Show-ErrorBox "Repo root does not exist:`n$RepoRoot"
        return
    }
    Start-Process "explorer.exe" -ArgumentList "`"$RepoRoot`""
}

function Open-Logs {
    if (-not (Test-Path $RepoRoot)) {
        Show-ErrorBox "Repo root does not exist:`n$RepoRoot"
        return
    }
    Start-Process "explorer.exe" -ArgumentList "`"$RepoRoot`""
}

# -------- GUI Layout --------

$form                      = New-Object System.Windows.Forms.Form
$form.Text                 = "Kydras Repo Tools (HTTPS Engine)"
$form.StartPosition        = "CenterScreen"
$form.Size                 = New-Object System.Drawing.Size(560, 520)
$form.MaximizeBox          = $false
$form.FormBorderStyle      = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.BackColor            = [System.Drawing.Color]::FromArgb(8,8,8)

if (Test-Path $IconPath) {
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($IconPath) } catch {}
}

$baseFont   = New-Object System.Drawing.Font("Segoe UI", 10)
$buttonFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$form.Font  = $baseFont

$goldColor  = [System.Drawing.Color]::FromArgb(212,175,55)
$labelGold  = [System.Drawing.Color]::FromArgb(230,190,80)

if (Test-Path $LogoPath) {
    $logoBox               = New-Object System.Windows.Forms.PictureBox
    $logoBox.Dock          = "Top"
    $logoBox.Height        = 140
    $logoBox.SizeMode      = "Zoom"
    $logoBox.BackColor     = [System.Drawing.Color]::FromArgb(10,10,10)
    $logoBox.Image         = [System.Drawing.Image]::FromFile($LogoPath)
    $form.Controls.Add($logoBox)
}

$subtitle                  = New-Object System.Windows.Forms.Label
$subtitle.Text             = "Kydras Systems Inc.  |  HTTPS Repo Engine  |  Nothing is off limits."
$subtitle.Dock             = "Top"
$subtitle.Height           = 24
$subtitle.TextAlign        = "MiddleCenter"
$subtitle.ForeColor        = $labelGold
$subtitle.BackColor        = [System.Drawing.Color]::FromArgb(16,16,16)
$form.Controls.Add($subtitle)

$statusLabel               = New-Object System.Windows.Forms.Label
$statusLabel.Dock          = "Bottom"
$statusLabel.Height        = 24
$statusLabel.TextAlign     = "MiddleLeft"
$statusLabel.ForeColor     = [System.Drawing.Color]::FromArgb(180,180,180)
$statusLabel.BackColor     = [System.Drawing.Color]::FromArgb(20,20,20)
$statusLabel.Padding       = New-Object System.Windows.Forms.Padding(8,0,8,0)
$statusLabel.Text          = "Status: initializing..."
$form.Controls.Add($statusLabel)
$script:StatusLabel = $statusLabel

$layout                    = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock               = "Fill"
$layout.RowCount           = 5
$layout.ColumnCount        = 2
$layout.Padding            = New-Object System.Windows.Forms.Padding(20, 10, 20, 20)
$layout.BackColor          = [System.Drawing.Color]::FromArgb(12,12,12)

for ($i=0; $i -lt $layout.RowCount; $i++) {
    $rowStyle = New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::Percent, 20)
    [void]$layout.RowStyles.Add($rowStyle)
}
for ($i=0; $i -lt $layout.ColumnCount; $i++) {
    $colStyle = New-Object System.Windows.Forms.ColumnStyle(
        [System.Windows.Forms.SizeType]::Percent, 50)
    [void]$layout.ColumnStyles.Add($colStyle)
}

function New-KydrasButton {
    param([string]$Text,[ScriptBlock]$OnClick)

    $btn                         = New-Object System.Windows.Forms.Button
    $btn.Text                    = $Text
    $btn.Dock                    = "Fill"
    $btn.Margin                  = New-Object System.Windows.Forms.Padding(8)
    $btn.Font                    = $buttonFont
    $btn.BackColor               = [System.Drawing.Color]::FromArgb(20,20,20)
    $btn.ForeColor               = $goldColor
    $btn.FlatStyle               = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize  = 1
    $btn.FlatAppearance.BorderColor = $goldColor
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35,27,10)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(50,35,12)
    $btn.Add_Click($OnClick)
    return $btn
}

$btnCloneAll     = New-KydrasButton "Clone All (user + org, HTTPS)"       { Run-CloneAll }
$btnCloneUser    = New-KydrasButton "Clone Scoped (user + org, HTTPS)"    { Run-CloneUser }
$btnSync         = New-KydrasButton "Repo Manager: Sync (HTTPS)"          { Run-RepoManagerMode "sync" }
$btnPolish       = New-KydrasButton "Repo Manager: Polish"                { Run-RepoManagerMode "polish" }
$btnPush         = New-KydrasButton "Repo Manager: Push"                  { Run-RepoManagerMode "push" }
$btnFullPipeline = New-KydrasButton "Run Full Pipeline"                   { Run-FullPipeline }
$btnOpenRepos    = New-KydrasButton "Open Repos Folder"                   { Open-ReposFolder }
$btnOpenLogs     = New-KydrasButton "Open Logs"                           { Open-Logs }
$btnUpdateTools  = New-KydrasButton "Update Tools (Build Bundle)"         { Run-BuildBundle }
$btnClose        = New-KydrasButton "Close"                               { $form.Close() }

$layout.Controls.Add($btnCloneAll,     0, 0)
$layout.Controls.Add($btnCloneUser,    1, 0)
$layout.Controls.Add($btnSync,         0, 1)
$layout.Controls.Add($btnPolish,       1, 1)
$layout.Controls.Add($btnPush,         0, 2)
$layout.Controls.Add($btnFullPipeline, 1, 2)
$layout.Controls.Add($btnOpenRepos,    0, 3)
$layout.Controls.Add($btnOpenLogs,     1, 3)
$layout.Controls.Add($btnUpdateTools,  0, 4)
$layout.Controls.Add($btnClose,        1, 4)

$form.Controls.Add($layout)

# Live refresh timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Refresh-StatusBar })
$timer.Start()

$form.Add_Shown({ Refresh-StatusBar })

[void]$form.ShowDialog()
'@

Set-Content -Path $GuiPath -Value $guiContent -Encoding UTF8
Write-Host "Updated GUI script: $GuiPath" -ForegroundColor Green

# ======================================
# E, F, G) Build bundle + launcher
# ======================================

$launcherContent = @'
#!/usr/bin/env pwsh
<#
Kydras-Enterprise-Launcher.ps1
Simple launcher shell for Kydras Enterprise Tools.
Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$AppsDir   = "K:\Kydras\Apps\CLI"
$GuiExe    = Join-Path $AppsDir "kydras-cli-gui.exe"
$CliExe    = Join-Path $AppsDir "kydras-cli.exe"

Write-Host "Kydras Enterprise Tools Launcher" -ForegroundColor Cyan
Write-Host "1) Launch GUI" -ForegroundColor Green
Write-Host "2) Launch CLI" -ForegroundColor Green
Write-Host "0) Exit" -ForegroundColor Yellow

$choice = Read-Host "Select"

switch ($choice) {
    "1" {
        if (Test-Path $GuiExe) {
            Start-Process $GuiExe
        }
        else {
            Write-Host "GUI exe not found at $GuiExe" -ForegroundColor Red
        }
    }
    "2" {
        if (Test-Path $CliExe) {
            Start-Process $CliExe
        }
        else {
            Write-Host "CLI exe not found at $CliExe" -ForegroundColor Red
        }
    }
    default { }
}
'@

Set-Content -Path $LauncherPath -Value $launcherContent -Encoding UTF8
Write-Host "Created launcher script: $LauncherPath" -ForegroundColor Green

$buildBundleContent = @'
#!/usr/bin/env pwsh
<#
Build-KydrasEnterpriseBundle.ps1

Builds:
  - kydras-cli.exe
  - kydras-cli-gui.exe
  - Kydras-Enterprise-Tools.exe
Updates:
  - Kydras-Tools-Version.txt

Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$AppsDir   = "K:\Kydras\Apps\CLI"
$GuiScript = Join-Path $AppsDir "kydras-cli-gui.ps1"
$GuiExe    = Join-Path $AppsDir "kydras-cli-gui.exe"
$CliScript = Join-Path $AppsDir "kydras-cli.ps1"
$CliExe    = Join-Path $AppsDir "kydras-cli.exe"
$Launcher  = Join-Path $AppsDir "Kydras-Enterprise-Launcher.ps1"
$BundleExe = Join-Path $AppsDir "Kydras-Enterprise-Tools.exe"
$IconPath  = Join-Path $AppsDir "kydras.ico"
$VersionFile = Join-Path $AppsDir "Kydras-Tools-Version.txt"

$ToolsVersion = "1.0.0"
$NowStamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "=== Build-KydrasEnterpriseBundle.ps1 ===" -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module ps2exe -ErrorAction Stop

function Build-Exe {
    param([string]$Input,[string]$Output,[string]$Title)

    $args = @{
        InputFile   = $Input
        OutputFile  = $Output
        NoConsole   = $true
        Title       = $Title
        Description = "Kydras Systems Inc. | Nothing is off limits."
        Company     = "Kydras Systems Inc."
        Product     = $Title
        Version     = $ToolsVersion
    }

    if (Test-Path $IconPath) {
        $args["Icon"] = $IconPath
    }

    Write-Host "Building $Output ..." -ForegroundColor Green
    Invoke-ps2exe @args
}

Build-Exe -Input $GuiScript -Output $GuiExe -Title "Kydras Repo Tools (GUI)"
Build-Exe -Input $CliScript -Output $CliExe -Title "Kydras Repo Tools (CLI)"
Build-Exe -Input $Launcher  -Output $BundleExe -Title "Kydras Enterprise Tools"

"Kydras Tools Version: $ToolsVersion" | Out-File -FilePath $VersionFile -Encoding UTF8
"Built at: $NowStamp"                 | Out-File -FilePath $VersionFile -Append

Write-Host ""
Write-Host "[✓] Bundle build complete." -ForegroundColor Green
Write-Host "Executables:" -ForegroundColor Green
Write-Host "  $GuiExe" -ForegroundColor Yellow
Write-Host "  $CliExe" -ForegroundColor Yellow
Write-Host "  $BundleExe" -ForegroundColor Yellow
Write-Host "Version stamp:" -ForegroundColor Green
Write-Host "  $VersionFile" -ForegroundColor Yellow
'@

Set-Content -Path $BuildBundlePath -Value $buildBundleContent -Encoding UTF8
Write-Host "Created build bundle script: $BuildBundlePath" -ForegroundColor Green

# ======================================
# A) Nightly Task Scheduler job
# ======================================

$taskName = "Kydras_FullPipeline_Nightly"
$taskCmd  = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$FullPipeline`""

Write-Host "Creating/Updating scheduled task: $taskName" -ForegroundColor Cyan

try {
    schtasks /Create /TN $taskName /TR $taskCmd /SC DAILY /ST 03:00 /RL HIGHEST /F /RU SYSTEM | Out-Null
    Write-Host "Scheduled task created/updated: $taskName (03:00 daily, SYSTEM)" -ForegroundColor Green
}
catch {
    Write-Host "WARNING: Failed to create scheduled task (run as admin to fix)." -ForegroundColor Yellow
    Write-Host $_
}

# Version file at top level too
"Kydras Tools Version: $Version" | Out-File -FilePath $VersionFile -Encoding UTF8
"Upgraded at: $NowStamp"         | Out-File -FilePath $VersionFile -Append

Write-Host ""
Write-Host "[✓] Kydras Enterprise Upgrade COMPLETE." -ForegroundColor Green
Write-Host "Backups stored at: $BackupDir" -ForegroundColor Yellow
Write-Host "Next: run Build-KydrasEnterpriseBundle.ps1 to build EXEs." -ForegroundColor Cyan
