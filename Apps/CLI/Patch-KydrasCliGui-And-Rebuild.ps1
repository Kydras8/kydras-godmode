<# 
    Patch-KydrasCliGui-And-Rebuild.ps1

    Purpose:
      - Automatically patch Kydras-CLI-GUI.ps1 so that ScriptDir resolution
        works both for the .ps1 and for the compiled EXE (no more empty Path error).
      - Then rerun Kydras-EnterpriseCLI-AutoSetup.ps1 to rebuild the EXE,
        recreate shortcuts, and regenerate the installer ZIP.

    Assumptions:
      - Base CLI directory: K:\Kydras\Apps\CLI
      - GUI script:        Kydras-CLI-GUI.ps1
      - Auto-setup script: Kydras-EnterpriseCLI-AutoSetup.ps1
#>

[CmdletBinding()]
param(
    [string]$BaseDir = 'K:\Kydras\Apps\CLI'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Kydras CLI GUI ScriptDir Patch + Rebuild ===" -ForegroundColor Yellow
Write-Host "BaseDir: $BaseDir" -ForegroundColor Cyan
Write-Host ""

# Paths
$GuiScriptPath   = Join-Path $BaseDir 'Kydras-CLI-GUI.ps1'
$AutoSetupScript = Join-Path $BaseDir 'Kydras-EnterpriseCLI-AutoSetup.ps1'

if (-not (Test-Path $GuiScriptPath)) {
    throw "GUI script not found at: $GuiScriptPath"
}

Write-Host "[*] Loading GUI script: $GuiScriptPath" -ForegroundColor DarkGray
$content = Get-Content -Path $GuiScriptPath -Raw

# --- Old PATHS block pattern (anything from '# --- PATHS' to $LogsRoot line) ----
$pattern = '(?ms)# --- PATHS.*?\$LogsRoot\s+=\s+''K:\\Kydras\\Logs''.*?\r?\n'

if (-not ([regex]::IsMatch($content, $pattern))) {
    Write-Warning "Could not find the expected PATHS block to patch."
    Write-Warning "No changes applied to $GuiScriptPath."
} else {
    Write-Host "[*] Patching PATHS block for robust ScriptDir detection..." -ForegroundColor DarkCyan

    $newBlock = @'
# --- PATHS -------------------------------------------------------------
# Resolve script directory in a way that works for both .ps1 and compiled EXE
if ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
elseif ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
}
else {
    # Fallback: current directory
    $ScriptDir = (Get-Location).Path
}

$RepoManagerScript  = Join-Path $ScriptDir 'Kydras-RepoManager.ps1'
$CloneScript        = Join-Path $ScriptDir 'Clone-All-KydrasRepos.ps1'
$PipelineScript     = Join-Path $ScriptDir 'Run-KydrasFullPipeline.ps1'
$BundleScript       = Join-Path $ScriptDir 'Build-KydrasEnterpriseBundle.ps1'
$LogsRoot           = 'K:\Kydras\Logs'
'@

    # Do the replacement
    $patched = [regex]::Replace($content, $pattern, $newBlock + "`r`n")

    if ($patched -eq $content) {
        Write-Warning "Pattern replacement did not change the file. Check the script manually."
    } else {
        Write-Host "[OK] PATHS block patched in memory." -ForegroundColor Green
        Set-Content -Path $GuiScriptPath -Value $patched -Encoding UTF8
        Write-Host "[OK] GUI script updated on disk: $GuiScriptPath" -ForegroundColor Green
    }
}

Write-Host ""

# --- Now rerun the auto-setup to rebuild EXE & shortcuts ----------------
if (Test-Path $AutoSetupScript) {
    Write-Host "[*] Running Kydras-EnterpriseCLI-AutoSetup.ps1 to rebuild EXE and installer..." -ForegroundColor Cyan

    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $AutoSetupScript

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Auto-setup script exited with code $LASTEXITCODE. Check its output for details."
    } else {
        Write-Host "[OK] Auto-setup completed successfully." -ForegroundColor Green
    }
}
else {
    Write-Warning "Auto-setup script not found at: $AutoSetupScript"
    Write-Warning "GUI script is patched, but EXE/installer were NOT rebuilt automatically."

    Write-Host ""
    Write-Host "To rebuild manually later, run:" -ForegroundColor Yellow
    Write-Host "  pwsh -ExecutionPolicy Bypass -File `"$AutoSetupScript`"" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Patch + rebuild process finished." -ForegroundColor Yellow
