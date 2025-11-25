<# 
    Build-KydrasEnterpriseRelease.ps1

    Purpose:
      - Read version.json
      - Optionally build a CLI EXE using ps2exe (if available)
      - Package all CLI assets into a versioned bundle folder
      - Create a ZIP under K:\Kydras\Bundles

    Output example:
      K:\Kydras\Bundles\Kydras-EnterpriseCLI-1.0.1-20251125-010203.zip
#>

[CmdletBinding()]
param(
    [switch]$SkipExe
)

$ErrorActionPreference = 'Stop'

# --- Paths -------------------------------------------------------------------

$AppsDir   = 'K:\Kydras\Apps\CLI'
$Bundles   = 'K:\Kydras\Bundles'
$LogsRoot  = 'K:\Kydras\Logs\EnterpriseCLI'

$VersionFile = Join-Path $AppsDir 'version.json'
$CliScript   = Join-Path $AppsDir 'Kydras-EnterpriseCLI.ps1'  # adjust if your main entry script has a different name
$ExeOutput   = Join-Path $AppsDir 'kydras-enterprise-cli.exe'

foreach ($dir in @($AppsDir, $Bundles, $LogsRoot)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BuildLog  = Join-Path $LogsRoot ("Build-KydrasEnterpriseRelease_{0}.log" -f $Timestamp)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $BuildLog -Append
}

Write-Log "=== Build-KydrasEnterpriseRelease started ==="
Write-Log "AppsDir : $AppsDir"
Write-Log "Bundles : $Bundles"
Write-Log "Logs    : $LogsRoot"

# --- Read version.json -------------------------------------------------------

if (-not (Test-Path $VersionFile)) {
    throw "version.json not found at $VersionFile"
}

$versionRaw = Get-Content $VersionFile -Raw
$versionObj = $versionRaw | ConvertFrom-Json

$major = [int]$versionObj.major
$minor = [int]$versionObj.minor
$patch = [int]$versionObj.patch
$build = [int]$versionObj.build

$VersionString = "{0}.{1}.{2}-b{3}" -f $major, $minor, $patch, $build
Write-Log "Version: $VersionString"

# --- Optional EXE build with ps2exe -----------------------------------------

$exeBuilt = $false

if (-not $SkipExe) {
    $ps2exeCmd = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue

    if ($ps2exeCmd) {
        if (-not (Test-Path $CliScript)) {
            Write-Log "[!] CLI script not found: $CliScript. Skipping EXE build."
        }
        else {
            Write-Log "ps2exe found: $($ps2exeCmd.Source)"
            Write-Log "Building EXE from $CliScript to $ExeOutput"

            try {
                # Basic ps2exe invocation. Adjust options as desired.
                Invoke-ps2exe -inputFile $CliScript -outputFile $ExeOutput -noConsole -x64 -title "Kydras Enterprise CLI" -noConfigFile 2>&1 |
                    ForEach-Object { Write-Log "ps2exe> $_" }

                if (Test-Path $ExeOutput) {
                    Write-Log "[OK] EXE built: $ExeOutput"
                    $exeBuilt = $true
                }
                else {
                    Write-Log "[!] ps2exe did not produce $ExeOutput. Continuing without EXE."
                }
            }
            catch {
                Write-Log "[!] ps2exe build failed: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Log "[!] Invoke-ps2exe not available. Skipping EXE build."
    }
}
else {
    Write-Log "SkipExe switch used. Skipping EXE build."
}

# --- Prepare bundle folder ---------------------------------------------------

$BundleName   = "Kydras-EnterpriseCLI-{0}-{1}" -f $VersionString, $Timestamp
$BundleFolder = Join-Path $Bundles $BundleName

if (Test-Path $BundleFolder) {
    Write-Log "[!] Bundle folder already exists. Removing: $BundleFolder"
    Remove-Item -Recurse -Force $BundleFolder
}

New-Item -ItemType Directory -Path $BundleFolder -Force | Out-Null
Write-Log "Bundle folder: $BundleFolder"

# Subfolder for payload
$PayloadFolder = Join-Path $BundleFolder 'payload'
New-Item -ItemType Directory -Path $PayloadFolder -Force | Out-Null

# --- Copy CLI assets into payload -------------------------------------------

Write-Log "Copying CLI assets into payload..."

# Copy all PS1 scripts and version.json
Get-ChildItem $AppsDir -Filter "*.ps1" | ForEach-Object {
    Copy-Item $_.FullName $PayloadFolder -Force
    Write-Log "Copied script: $($_.Name)"
}

Copy-Item $VersionFile $PayloadFolder -Force
Write-Log "Copied version.json"

# Copy EXE if built
if ($exeBuilt -and (Test-Path $ExeOutput)) {
    Copy-Item $ExeOutput $PayloadFolder -Force
    Write-Log "Copied EXE: $(Split-Path $ExeOutput -Leaf)"
}

# Copy config folder if it exists
$ConfigDir = Join-Path $AppsDir 'config'
if (Test-Path $ConfigDir) {
    $ConfigTarget = Join-Path $PayloadFolder 'config'
    Copy-Item $ConfigDir $ConfigTarget -Recurse -Force
    Write-Log "Copied config folder."
}

# --- Add README into bundle --------------------------------------------------

$ReadmePath = Join-Path $BundleFolder 'README-KydrasEnterpriseCLI.txt'

@"
Kydras Enterprise CLI
=====================

Version: $VersionString
Built:   $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

Contents:
  - payload\*.ps1               : Core CLI scripts
  - payload\version.json        : Version metadata
  - payload\kydras-enterprise-cli.exe (optional) : Compiled CLI (if ps2exe available)
  - payload\config\*            : Configuration and managed-repos list

Quick Start:
  1. Extract this ZIP to a folder of your choice (e.g., K:\Kydras\Apps\CLI-Release).
  2. Open PowerShell 7 (pwsh) in that folder.
  3. Run:
       pwsh -ExecutionPolicy Bypass -File .\Kydras-EnterpriseCLI.ps1
     (or the EXE if included)

Logs:
  - CLI logs are stored under K:\Kydras\Logs (RepoManager, Pipeline, Build, etc.)

Notes:
  - This package was auto-built by Build-KydrasEnterpriseRelease.ps1
"@ | Set-Content -Path $ReadmePath -Encoding UTF8

Write-Log "README written: $ReadmePath"

# --- Create ZIP -------------------------------------------------------------

$ZipPath = "$BundleFolder.zip"

if (Test-Path $ZipPath) {
    Write-Log "[!] Removing existing ZIP: $ZipPath"
    Remove-Item $ZipPath -Force
}

Write-Log "Creating ZIP: $ZipPath"
Compress-Archive -Path $BundleFolder\* -DestinationPath $ZipPath -Force
Write-Log "[OK] ZIP created."

Write-Log "=== Build-KydrasEnterpriseRelease completed successfully ==="
Write-Host "[OK] Release bundle created: $ZipPath" -ForegroundColor Green
Write-Host "Log: $BuildLog"
