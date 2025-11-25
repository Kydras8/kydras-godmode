<# 
    Publish-KydrasEnterpriseRelease.ps1

    Creates a GitHub Release for the current Kydras Enterprise CLI version.

    Requirements:
      - GitHub CLI (gh) installed
      - gh auth status == logged in with appropriate permissions
      - version.json present
      - Latest installer ZIP in BundlesDir
      - EXE present in BaseDir

    Example:

      pwsh -EP Bypass -File ".\Publish-KydrasEnterpriseRelease.ps1" -Version 1.2.3 -Message "New pipeline features"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,

    [string]$Message = "Automated release",

    [string]$Repo = 'Kydras8/Kydras-GodBox'
)

$ErrorActionPreference = 'Stop'

# Resolve base and bundles dirs
$BaseDir    = Split-Path -Parent $PSCommandPath
$BundlesDir = 'K:\Kydras\Bundles'

Write-Host "=== Publish Kydras Enterprise CLI Release ===" -ForegroundColor Yellow
Write-Host "Repo      : $Repo"       -ForegroundColor Cyan
Write-Host "BaseDir   : $BaseDir"    -ForegroundColor Cyan
Write-Host "BundlesDir: $BundlesDir" -ForegroundColor Cyan
Write-Host ""

# --- Ensure gh ---------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' not found. Install from https://cli.github.com/ and rerun."
}

try {
    gh auth status | Out-Null
} catch {
    throw "gh auth status failed. Run 'gh auth login' first."
}

# --- Resolve version ---------------------------------------------------
$VersionFile = Join-Path $BaseDir 'version.json'
if (-not $Version -and (Test-Path $VersionFile)) {
    $meta = Get-Content -Path $VersionFile -Raw | ConvertFrom-Json
    if ($meta.version) {
        $Version = [string]$meta.version
    }
}

if (-not $Version) {
    throw "Version not supplied and could not be read from version.json."
}

$tag   = "v$Version"
$title = "Kydras Enterprise CLI $Version"

# --- Locate EXE and latest installer ZIP -------------------------------
$ExePath = Join-Path $BaseDir 'kydras-cli-gui.exe'
if (-not (Test-Path $ExePath)) {
    throw "EXE not found at $ExePath"
}

$latestZip = Get-ChildItem -Path $BundlesDir -Filter 'Kydras-EnterpriseCLI-Installer-*.zip' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

if (-not $latestZip) {
    throw "No installer ZIPs found under $BundlesDir"
}

Write-Host "[OK] Using EXE   : $ExePath" -ForegroundColor Green
Write-Host "[OK] Using ZIP   : $($latestZip.FullName)" -ForegroundColor Green
Write-Host "[*] Release tag  : $tag" -ForegroundColor Cyan
Write-Host ""

# --- Build notes file --------------------------------------------------
$notesPath = Join-Path $env:TEMP ("kydras-release-notes-$tag.txt")

$notes = @()
$notes += "Kydras Enterprise CLI $Version"
$notes += ""
$notes += $Message
$notes += ""
$notes += "Assets:"
$notes += " - kydras-cli-gui.exe"
$notes += " - $([System.IO.Path]::GetFileName($latestZip.FullName))"
$notes += ""
$notesText = $notes -join "`r`n"

Set-Content -Path $notesPath -Value $notesText -Encoding UTF8

Write-Host "[*] Creating GitHub release on $Repo with tag $tag ..." -ForegroundColor Cyan

# gh release create <tag> <files...> --repo <owner/repo> --notes-file <file> --title <title>
gh release create $tag `
    "$ExePath#Kydras Enterprise CLI.exe" `
    "$($latestZip.FullName)#Kydras Enterprise CLI Installer ZIP" `
    --repo $Repo `
    --notes-file $notesPath `
    --title "$title"

Write-Host ""
Write-Host "[OK] GitHub release created: $tag" -ForegroundColor Green
