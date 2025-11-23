[CmdletBinding()]
param(
    [string]$Version   = "0.0.0",
    [string]$OutputDir = $(Join-Path $PSScriptRoot "..\Bundles")
)

$ErrorActionPreference = "Stop"

Write-Host "=== Build-KydrasEnterpriseBundle ===" -ForegroundColor Cyan
Write-Host "Version   : $Version"
Write-Host "OutputDir : $OutputDir"
Write-Host ""

if (-not (Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    throw "Invoke-ps2exe not found. Please install module 'ps2exe' in PowerShell 7: Install-Module ps2exe -Scope CurrentUser"
}

$cliScript = Join-Path $PSScriptRoot "Kydras-EnterpriseCLI.ps1"
if (-not (Test-Path -LiteralPath $cliScript)) {
    throw "Main CLI script not found at: $cliScript"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    Write-Host "Creating OutputDir: $OutputDir"
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$exeName = "Kydras-EnterpriseCLI-$Version.exe"
$zipName = "Kydras-EnterpriseCLI-$Version.zip"

$exePath = Join-Path $OutputDir $exeName
$zipPath = Join-Path $OutputDir $zipName

Write-Host "Building EXE: $exePath"
Invoke-ps2exe -inputFile $cliScript `
              -outputFile $exePath `
              -noConsole `
              -x64 `
              -title "Kydras Enterprise CLI $Version"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "ps2exe did not produce output EXE at: $exePath"
}

Write-Host "Creating installer ZIP: $zipPath"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path $exePath, $cliScript -DestinationPath $zipPath -Force

Write-Host "Build complete."
Write-Host "EXE : $exePath"
Write-Host "ZIP : $zipPath"
