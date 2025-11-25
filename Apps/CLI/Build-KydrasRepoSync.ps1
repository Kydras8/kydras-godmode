# Kydras Systems Inc. - Build KydrasRepoSync.exe from latest clone script

Set-Location -Path "K:\Kydras\Apps\CLI"

Write-Host "[Build] Looking for Clone-All-KydrasRepos*.ps1 scripts..."

$scriptFile = Get-ChildItem -Filter "Clone-All-KydrasRepos*.ps1" |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

if (-not $scriptFile) {
    throw "[Build] No clone script found in $(Get-Location)"
}

Write-Host "[Build] Using script: $($scriptFile.Name)"

# Ensure ps2exe is available
if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "[Build] Importing ps2exe module..."
    Import-Module ps2exe -ErrorAction Stop
}

# Icon (optional)
$iconPath = "K:\Kydras\Apps\CLI\kydras.ico"
if (-not (Test-Path $iconPath)) {
    Write-Host "[Build] WARNING: Icon '$iconPath' not found. Building without icon."
    $iconPath = $null
}

$exeName = "KydrasRepoSync.exe"
$exePath = Join-Path (Get-Location) $exeName

Write-Host "[Build] Building $exeName from $($scriptFile.Name)..."

$invokeParams = @{
    InputFile  = $scriptFile.FullName
    OutputFile = $exePath
    NoConsole  = $true
}
if ($iconPath) { $invokeParams.Icon = $iconPath }

Invoke-ps2exe @invokeParams

Write-Host "[Build] Done. Created $exeName at $exePath"
