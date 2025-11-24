[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Args
)

$ErrorActionPreference = "Stop"

# Directory of this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Underlying bootstrap script (CHANGE THIS if your real entrypoint has a different name)
$bootstrap = Join-Path $scriptDir "Kydras-EnterpriseCLI-AutoSetup.ps1"

if (Test-Path -LiteralPath $bootstrap) {
    & $bootstrap @Args
}
else {
    Write-Error "Bootstrap script not found at: $bootstrap"
}
