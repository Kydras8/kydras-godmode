#!/usr/bin/env pwsh
<#
build-kydras-cli.ps1
------------------------------------
Auto-compiler for Kydras Repo Tools (HTTPS Engine).

What it does:
  - Ensures ps2exe is installed
  - Kills any running kydras-cli*.exe
  - Builds:
      - kydras-cli-gui.exe (GUI front-end, HTTPS-aware)
      - kydras-cli.exe     (console menu, HTTPS-aware)
  - Uses kydras.ico as the EXE icon (if present)
  - Logs to _build-kydras-cli.log

Usage:
  pwsh -ExecutionPolicy Bypass -File .\build-kydras-cli.ps1
  pwsh -ExecutionPolicy Bypass -File .\build-kydras-cli.ps1 -GuiOnly
  pwsh -ExecutionPolicy Bypass -File .\build-kydras-cli.ps1 -ConsoleOnly
#>

[CmdletBinding()]
param(
    [switch]$GuiOnly,
    [switch]$ConsoleOnly
)

$ErrorActionPreference = "Stop"

# ------------------ CONFIG ------------------
$BaseDir        = "K:\Kydras\Apps\CLI"

$GuiScript      = Join-Path $BaseDir "kydras-cli-gui.ps1"
$GuiExe         = Join-Path $BaseDir "kydras-cli-gui.exe"

$CliScript      = Join-Path $BaseDir "kydras-cli.ps1"
$CliExe         = Join-Path $BaseDir "kydras-cli.exe"

$IconPath       = Join-Path $BaseDir "kydras.ico"
$BuildLog       = Join-Path $BaseDir "_build-kydras-cli.log"

$AppTitleGui    = "Kydras Repo Tools (GUI, HTTPS)"
$AppTitleCli    = "Kydras Repo Tools (CLI, HTTPS)"

$AppDescription = "Kydras Systems Inc. | HTTPS Repo Engine | Nothing is off limits."
$AppCompany     = "Kydras Systems Inc."
$AppVersion     = "1.0.0.0"

# ------------------ LOG HELPERS ------------------

function Write-BuildLog {
    param([string]$Message)
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[${ts}] $Message"
    $line | Out-File -FilePath $BuildLog -Append
    Write-Host $line
}

Write-BuildLog ""
Write-BuildLog "===== build-kydras-cli.ps1 invoked ====="

# ------------------ PRECHECKS ------------------

if (-not (Test-Path $BaseDir)) {
    throw "Base directory not found: $BaseDir"
}

Set-Location $BaseDir

function Ensure-File {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path $Path)) {
        throw "Missing required file: $Description at $Path"
    }
}

if (-not $ConsoleOnly) {
    Ensure-File -Path $GuiScript -Description "GUI script (kydras-cli-gui.ps1)"
}
if (-not $GuiOnly) {
    Ensure-File -Path $CliScript -Description "CLI script (kydras-cli.ps1)"
}

if (-not (Test-Path $IconPath)) {
    Write-BuildLog "WARNING: Icon file not found at $IconPath. EXEs will build without custom icon."
}

# ------------------ ENSURE PS2EXE ------------------

Write-BuildLog "Checking for ps2exe module..."

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-BuildLog "ps2exe not found. Installing..."
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-BuildLog "ps2exe module installed."
    }
    catch {
        Write-BuildLog "ERROR: Failed to install ps2exe: $_"
        throw
    }
}
else {
    Write-BuildLog "ps2exe module already installed."
}

Import-Module ps2exe -ErrorAction Stop

# ------------------ KILL RUNNING EXEs ------------------

Write-BuildLog "Killing any running kydras-cli*.exe processes..."

$targets = @("kydras-cli.exe","kydras-cli-gui.exe")

foreach ($t in $targets) {
    try {
        taskkill /IM $t /F /T 2>$null | Out-Null
        Write-BuildLog "Attempted kill: $t (ignore 'not found' messages)."
    }
    catch {
        Write-BuildLog "Non-fatal error killing $t : $_"
    }
}

Start-Sleep -Seconds 1

# ------------------ BUILD FUNCTION ------------------

function Invoke-BuildExe {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string]$Title,
        [string]$Description,
        [string]$Company,
        [string]$Version,
        [bool]$UseIcon
    )

    Write-BuildLog "Compiling: $InputFile -> $OutputFile"

    $commonArgs = @{
        InputFile   = $InputFile
        OutputFile  = $OutputFile
        NoConsole   = $true
        Title       = $Title
        Description = $Description
        Company     = $Company
        Product     = $Title
        Version     = $Version
    }

    if ($UseIcon -and (Test-Path $IconPath)) {
        # ps2exe uses -Icon or -IconFile depending on version; -Icon works in your manual calls
        $commonArgs["Icon"] = $IconPath
    }

    try {
        Invoke-ps2exe @commonArgs
        Write-BuildLog "SUCCESS: Built $OutputFile"
    }
    catch {
        Write-BuildLog "ERROR: Failed to build $OutputFile : $_"
        throw
    }
}

# ------------------ BUILD PIPELINE ------------------

$buildGui = -not $ConsoleOnly
$buildCli = -not $GuiOnly

if ($buildGui) {
    Invoke-BuildExe -InputFile $GuiScript `
                    -OutputFile $GuiExe `
                    -Title $AppTitleGui `
                    -Description $AppDescription `
                    -Company $AppCompany `
                    -Version $AppVersion `
                    -UseIcon $true
}

if ($buildCli) {
    Invoke-BuildExe -InputFile $CliScript `
                    -OutputFile $CliExe `
                    -Title $AppTitleCli `
                    -Description $AppDescription `
                    -Company $AppCompany `
                    -Version $AppVersion `
                    -UseIcon $true
}

Write-BuildLog "===== build-kydras-cli.ps1 completed ====="
Write-Host ""
Write-Host "[✓] Kydras CLI build finished (HTTPS engine). See build log for details:" -ForegroundColor Green
Write-Host "    $BuildLog" -ForegroundColor Yellow
