<# ============================================================================
    Initialize-KydrasEnterpriseCLIRepo.ps1
    Purpose:
      - Ensure README.md, proprietary license, and CLI section exist
      - Create any needed folders
      - Remove merge conflict markers
      - Idempotent + future proof

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
$AppsDir         = Join-Path $RepoRoot 'Apps'
$CliDir          = Join-Path $AppsDir 'CLI'

$LicensePath = Join-Path $RepoRoot $LicenseFileName
$ReadmePath  = Join-Path $RepoRoot $ReadmeFileName

$LogsRoot    = 'K:\Kydras\Logs\RepoSetup'
$Timestamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile     = Join-Path $LogsRoot ("InitializeRepo_{0}.log" -f $Timestamp)

$BackupRoot  = Join-Path $RepoRoot 'Backups'
$BackupDir   = Join-Path $BackupRoot ("RepoMeta-{0}" -f $Timestamp)

# Helpers
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

function Backup-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        Ensure-Directory $BackupDir
        $name = Split-Path $Path -Leaf
        Copy-Item $Path (Join-Path $BackupDir $name) -Force
        Write-Log "Backed up $name"
    }
}

# Ensure directories
Ensure-Directory $LogsRoot
Ensure-Directory $BackupRoot
Ensure-Directory $AppsDir
Ensure-Directory $CliDir

Write-Log "=== Initialize-KydrasEnterpriseCLIRepo started ==="
Write-Log "RepoRoot: $RepoRoot"

# -------------------------------
# 1. Write Proprietary License
# -------------------------------
Backup-IfExists $LicensePath

$LicenseText = @"
Kydras Systems Inc. Proprietary Software License
Copyright (c) 2025 Kydras Systems Inc.

This software is the exclusive property of Kydras Systems Inc.
You may NOT copy, modify, distribute, sublicense, or reverse-engineer it.

All rights reserved. For commercial agreements, contact:
admin@kydras-systems-inc.com
"@

$LicenseText | Set-Content $LicensePath -Encoding UTF8
Write-Log "License written."

# -------------------------------
# 2. Ensure README exists
# -------------------------------
if (-not (Test-Path $ReadmePath)) {

$DefaultReadme = @"
<!-- Kydras Repo Header -->
<p align="center">
  <strong>Kydras Systems Inc.</strong><br/>
  <em>Nothing is off limits.</em>
</p>

---

# ⚡ Kydras GODMODE Bootstrapper

Run in PowerShell 7+:

```powershell
iwr https://raw.githubusercontent.com/Kydras8/kydras-godmode/main/bootstrap-godmode.ps1 | iex

## 🧠 Kydras Enterprise CLI

The **Kydras Enterprise CLI** lives in `Apps/CLI` and provides:

- Repo Manager menu (`Kydras-RepoManager.ps1`)
- Full Pipeline orchestration (`Run-KydrasFullPipeline.ps1`)
- Versioning (`version.json` + `Update-KydrasEnterpriseCli.ps1`)
- Release bundle builder (`Build-KydrasEnterpriseRelease.ps1`)

Basic usage (on a Kydras dev box):

```powershell
Set-Location "K:\Kydras\Apps\CLI"
pwsh -ExecutionPolicy Bypass -File ".\Kydras-RepoManager.ps1"
```


## 📄 License

This repository is licensed under the **Kydras Systems Inc. Proprietary Software License**.
All rights reserved. Redistribution and modification are prohibited without written authorization from Kydras Systems Inc.

