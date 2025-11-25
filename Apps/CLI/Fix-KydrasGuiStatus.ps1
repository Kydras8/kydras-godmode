#!/usr/bin/env pwsh
<#
Fix-KydrasGuiStatus.ps1
- Backs up kydras-cli-gui.ps1
- Fixes all "$Prefix: ..." strings to use ${Prefix}: to avoid parser errors
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$BaseDir   = "K:\Kydras\Apps\CLI"
$GuiScript = Join-Path $BaseDir "kydras-cli-gui.ps1"
$Backup    = Join-Path $BaseDir "kydras-cli-gui.ps1.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "=== Fix-KydrasGuiStatus.ps1 ===" -ForegroundColor Cyan

if (-not (Test-Path $GuiScript)) {
    throw "GUI script not found at: $GuiScript"
}

Write-Host "Backing up GUI script to:" -ForegroundColor Yellow
Write-Host "  $Backup" -ForegroundColor Yellow
Copy-Item $GuiScript $Backup -Force

# Load file
$content = Get-Content $GuiScript -Raw

# Targeted replacements for Get-LogStatus strings
$replacements = @{
    '"$Prefix: (no runs yet)"'            = '"${Prefix}: (no runs yet)"'
    '"$Prefix: (log empty)"'              = '"${Prefix}: (log empty)"'
    '"$Prefix: (log has only blank lines)"' = '"${Prefix}: (log has only blank lines)"'
    '"$Prefix: (error reading log)"'      = '"${Prefix}: (error reading log)"'
    '"$Prefix: $ts — $msg"'               = '"${Prefix}: $ts — $msg"'
    '"$Prefix: $line"'                    = '"${Prefix}: $line"'
}

foreach ($pair in $replacements.GetEnumerator()) {
    if ($content -like "*$($pair.Key.Trim('"'))*") {
        Write-Host "Patching: $($pair.Key) -> $($pair.Value)" -ForegroundColor Green
        $content = $content.Replace($pair.Key, $pair.Value)
    }
}

# Save updated content
Set-Content -Path $GuiScript -Value $content -Encoding UTF8

Write-Host "Patch complete." -ForegroundColor Green
Write-Host "Rebuilding GUI EXE..." -ForegroundColor Cyan

# Rebuild GUI only using existing build script (if present)
$BuildScript = Join-Path $BaseDir "build-kydras-cli.ps1"
if (Test-Path $BuildScript) {
    try {
        pwsh -ExecutionPolicy Bypass -File $BuildScript -GuiOnly
    }
    catch {
        Write-Host "WARNING: build-kydras-cli.ps1 failed, but GUI script is patched." -ForegroundColor Yellow
        Write-Host $_
    }
}
else {
    Write-Host "NOTE: build-kydras-cli.ps1 not found. GUI EXE not rebuilt automatically." -ForegroundColor Yellow
    Write-Host "You can rebuild manually:" -ForegroundColor Yellow
    Write-Host '  pwsh -ExecutionPolicy Bypass -File .\build-kydras-cli.ps1 -GuiOnly'
}

Write-Host "`n[✓] Fix-KydrasGuiStatus complete." -ForegroundColor Green
