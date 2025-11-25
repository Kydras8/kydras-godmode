<# 
    Initialize-KydrasEnterpriseCLIRepo.ps1
    Simple, robust, no here-strings.

    - Ensures Apps/CLI exists
    - Ensures proprietary license at repo root
    - Ensures README.md exists
    - Cleans merge conflict markers
    - Adds Kydras Enterprise CLI note and License section if missing
#>

[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot -or [string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSCommandPath
}

# Paths
$LicenseFileName = 'LICENSE-KYDRAS-PROPRIETARY.txt'
$ReadmeFileName  = 'README.md'

$LicensePath = Join-Path $RepoRoot $LicenseFileName
$ReadmePath  = Join-Path $RepoRoot $ReadmeFileName

$AppsDir     = Join-Path $RepoRoot 'Apps'
$CliDir      = Join-Path $AppsDir 'CLI'

$LogsRoot    = 'K:\Kydras\Logs\RepoSetup'
$Timestamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile     = Join-Path $LogsRoot ("InitializeRepo_{0}.log" -f $Timestamp)

# Helpers
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-LogLine {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (Test-Path $Path) {
        $backupDir = Join-Path (Split-Path $Path -Parent) "Backups"
        Ensure-Directory $backupDir
        $name = Split-Path $Path -Leaf
        $backupName = "{0}.{1}.bak" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss')
        $dest = Join-Path $backupDir $backupName
        Copy-Item $Path $dest -Force
        Write-LogLine ("Backed up {0} to {1}" -f $name, $dest)
    }
}

# Ensure directories
Ensure-Directory $LogsRoot
Ensure-Directory $AppsDir
Ensure-Directory $CliDir

Write-LogLine "=== Initialize-KydrasEnterpriseCLIRepo started ==="
Write-LogLine ("RepoRoot: {0}" -f $RepoRoot)

# 1) Write proprietary license (always overwrite with latest text)
Backup-File $LicensePath

$licenseLines = @(
    'Kydras Systems Inc. Proprietary Software License',
    'Copyright (c) 2025 Kydras Systems Inc.',
    '',
    'This software and its associated documentation (the "Software") are the exclusive property of Kydras Systems Inc.',
    'You may NOT copy, modify, distribute, sublicense, or reverse-engineer the Software.',
    '',
    'All rights reserved.',
    'For commercial licensing or enterprise agreements, contact: admin@kydras-systems-inc.com'
)

$licenseLines | Set-Content -Path $LicensePath -Encoding UTF8
Write-LogLine "License file written."

# 2) Ensure README exists (minimal default if missing)
if (-not (Test-Path $ReadmePath)) {
    $defaultReadmeLines = @(
        '<!-- Kydras Repo Header -->',
        '<p align="center">',
        '  <strong>Kydras Systems Inc.</strong><br/>',
        '  <em>Nothing is off limits.</em>',
        '</p>',
        '',
        '---',
        '',
        '# ⚡ Kydras GODMODE Bootstrapper',
        '',
        'Run this in PowerShell 7+ to bootstrap GODMODE:',
        '',
        '```powershell',
        'iwr https://raw.githubusercontent.com/Kydras8/kydras-godmode/main/bootstrap-godmode.ps1 | iex',
        '```',
        ''
    )
    $defaultReadmeLines | Set-Content -Path $ReadmePath -Encoding UTF8
    Write-LogLine "README.md created with default content."
}

# 3) Clean merge conflict markers from README (<<<<<<<, =======, >>>>>>>)
$readmeLines = Get-Content $ReadmePath
$hasMarkers = $false

$cleanReadmeLines = @()
foreach ($line in $readmeLines) {
    if ($line -match '^<<<<<<<' -or $line -match '^=======' -or $line -match '^>>>>>>>') {
        $hasMarkers = $true
        continue
    }
    $cleanReadmeLines += $line
}

if ($hasMarkers) {
    Backup-File $ReadmePath
    $cleanReadmeLines | Set-Content -Path $ReadmePath -Encoding UTF8
    Write-LogLine "Merge conflict markers removed from README.md."
}

# 4) Ensure README contains a Kydras Enterprise CLI mention
$readmeText = Get-Content $ReadmePath -Raw

if ($readmeText -notmatch 'Kydras Enterprise CLI') {
    $cliSectionLines = @(
        '',
        '## 🧠 Kydras Enterprise CLI',
        '',
        'The **Kydras Enterprise CLI** lives in `Apps/CLI` and provides:',
        '',
        '- Repo Manager menu (`Kydras-RepoManager.ps1`)',
        '- Full Pipeline orchestration (`Run-KydrasFullPipeline.ps1`)',
        '- Versioning (`version.json` + `Update-KydrasEnterpriseCli.ps1`)',
        '- Release bundle builder (`Build-KydrasEnterpriseRelease.ps1`)',
        '',
        'Basic usage (on a Kydras dev box):',
        '',
        '```powershell',
        'Set-Location "K:\Kydras\Apps\CLI"',
        'pwsh -ExecutionPolicy Bypass -File ".\Kydras-RepoManager.ps1"',
        '```',
        ''
    )
    $cliSectionLines | Add-Content -Path $ReadmePath -Encoding UTF8
    Write-LogLine "CLI section appended to README.md."
} else {
    Write-LogLine "CLI section already present in README.md."
}

# 5) Ensure README has a License section
$readmeText = Get-Content $ReadmePath -Raw

if ($readmeText -notmatch '## 📄 License') {
    $licenseSectionLines = @(
        '',
        '## 📄 License',
        '',
        'This repository is licensed under the **Kydras Systems Inc. Proprietary Software License**.',
        'All rights reserved. Redistribution and modification are prohibited without written authorization from Kydras Systems Inc.',
        ''
    )
    $licenseSectionLines | Add-Content -Path $ReadmePath -Encoding UTF8
    Write-LogLine "License section appended to README.md."
} else {
    Write-LogLine "License section already present in README.md."
}

Write-LogLine "=== Initialize-KydrasEnterpriseCLIRepo completed ==="
Write-Host "[OK] Kydras Enterprise CLI repo metadata initialized." -ForegroundColor Green
Write-Host ("Log: {0}" -f $LogFile)
