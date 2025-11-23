[CmdletBinding()]
param(
    [ValidateSet("major","minor","patch")]
    [string]$BumpType = "patch",

    [string]$ChangeSummary = "Local full pipeline run",

    [string]$BundlesDir = "K:\Kydras\Bundles"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Run-KydrasFullPipeline ===" -ForegroundColor Cyan
Write-Host "BumpType   : $BumpType"
Write-Host "BundlesDir : $BundlesDir"
Write-Host ""

$updateScriptPath = Join-Path $PSScriptRoot "Update-KydrasEnterpriseCli.ps1"
if (-not (Test-Path -LiteralPath $updateScriptPath)) {
    throw "Update script not found at: $updateScriptPath"
}

& $updateScriptPath -BumpType $BumpType -ChangeSummary $ChangeSummary -BundlesDir $BundlesDir

Write-Host ""
Write-Host "Full pipeline completed."
