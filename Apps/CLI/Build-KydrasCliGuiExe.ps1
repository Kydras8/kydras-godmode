<# 
    Build-KydrasCliGuiExe.ps1

    Builds a standalone EXE for the Kydras CLI GUI using ps2exe.

    Output:
      K:\Kydras\Apps\CLI\kydras-cli-gui.exe
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $PSCommandPath
$GuiScript   = Join-Path $ScriptDir 'Kydras-CLI-GUI.ps1'
$OutputExe   = Join-Path $ScriptDir 'kydras-cli-gui.exe'

Write-Host "=== Kydras GUI EXE Builder ===" -ForegroundColor Yellow
Write-Host "Script : $GuiScript"
Write-Host "Output : $OutputExe"
Write-Host ""

if (-not (Test-Path $GuiScript)) {
    throw "GUI script not found at: $GuiScript"
}

try {
    Write-Host "[1/3] Importing ps2exe module ..." -ForegroundColor Cyan
    Import-Module ps2exe -ErrorAction Stop
}
catch {
    Write-Warning "Failed to import ps2exe. Install it with:"
    Write-Warning "  Install-Module ps2exe -Scope CurrentUser -Force"
    throw
}

if (Test-Path $OutputExe) {
    Write-Host "[2/3] Removing existing EXE ..." -ForegroundColor Cyan
    Remove-Item -Path $OutputExe -Force
}

Write-Host "[3/3] Building EXE with Invoke-ps2exe ..." -ForegroundColor Cyan

Invoke-ps2exe -inputFile $GuiScript `
              -outputFile $OutputExe `
              -noConsole `
              -x64 `
              -title "Kydras Enterprise CLI" `
              -company "Kydras Systems Inc." `
              -product "Kydras Enterprise CLI GUI" `
              -description "Kydras black-gold enterprise control panel" `
              -iconFile $null

if (-not (Test-Path $OutputExe)) {
    throw "ps2exe did not produce output at expected path: $OutputExe"
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
Write-Host "EXE created at: $OutputExe" -ForegroundColor Green
