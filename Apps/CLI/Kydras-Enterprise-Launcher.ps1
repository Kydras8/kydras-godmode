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
