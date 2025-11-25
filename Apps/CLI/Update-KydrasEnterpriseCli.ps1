<# 
    Update-KydrasEnterpriseCLI.ps1 (hardened)

    Purpose:
      - Bump version (Major / Minor / Patch / Build)
      - Maintain a stable JSON schema:
            {
              "major": 1,
              "minor": 0,
              "patch": 0,
              "build": 0,
              "lastUpdated": "ISO-8601"
            }
      - Auto-heal any weird or broken version.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Major','Minor','Patch','Build')]
    [string]$Bump = 'Patch',

    [Parameter(Mandatory = $false)]
    [string]$Message = 'Kydras Enterprise CLI version update'
)

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $PSCommandPath
$VersionFile = Join-Path $ScriptDir 'version.json'

function New-DefaultVersionObject {
    param()

    return [pscustomobject]@{
        major       = 1
        minor       = 0
        patch       = 0
        build       = 0
        lastUpdated = (Get-Date).ToString('o')
    }
}

function Normalize-VersionObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    # If it's not a PSCustomObject, or doesn't look like a version object, reset to default
    if (-not ($InputObject -is [pscustomobject])) {
        return New-DefaultVersionObject
    }

    $props = $InputObject.PSObject.Properties.Name

    $major = 1
    $minor = 0
    $patch = 0
    $build = 0
    $last  = (Get-Date).ToString('o')

    if ($props -contains 'major' -and $InputObject.major -ne $null) {
        [void][int]::TryParse($InputObject.major.ToString(), [ref]$major)
    }

    if ($props -contains 'minor' -and $InputObject.minor -ne $null) {
        [void][int]::TryParse($InputObject.minor.ToString(), [ref]$minor)
    }

    if ($props -contains 'patch' -and $InputObject.patch -ne $null) {
        [void][int]::TryParse($InputObject.patch.ToString(), [ref]$patch)
    }

    if ($props -contains 'build' -and $InputObject.build -ne $null) {
        [void][int]::TryParse($InputObject.build.ToString(), [ref]$build)
    }

    if ($props -contains 'lastUpdated' -and $InputObject.lastUpdated) {
        $last = $InputObject.lastUpdated.ToString()
    }

    return [pscustomobject]@{
        major       = $major
        minor       = $minor
        patch       = $patch
        build       = $build
        lastUpdated = $last
    }
}

function Get-VersionObject {
    if (-not (Test-Path $VersionFile)) {
        Write-Host "[!] version.json not found, creating a default one..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    $raw = Get-Content $VersionFile -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Host "[!] version.json is empty, using default values..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    try {
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "[!] version.json is invalid JSON, replacing with default..." -ForegroundColor Yellow
        return New-DefaultVersionObject
    }

    return Normalize-VersionObject -InputObject $obj
}

Write-Host "=== Kydras Enterprise CLI Updater ==="
Write-Host "Version file: $VersionFile"

$version = Get-VersionObject

$oldVersionString = "{0}.{1}.{2} (build {3})" -f $version.major, $version.minor, $version.patch, $version.build
Write-Host "[*] Current version: $oldVersionString"

switch ($Bump) {
    'Major' {
        $version.major++
        $version.minor = 0
        $version.patch = 0
        $version.build = 0
    }
    'Minor' {
        $version.minor++
        $version.patch = 0
        $version.build = 0
    }
    'Patch' {
        $version.patch++
        $version.build = 0
    }
    'Build' {
        $version.build++
    }
}

# Always bump build at least once per run if we didn't explicitly bump Build
if ($Bump -ne 'Build') {
    $version.build++
}

$version.lastUpdated = (Get-Date).ToString('o')

$newVersionString = "{0}.{1}.{2} (build {3})" -f $version.major, $version.minor, $version.patch, $version.build
Write-Host "[OK] New version: $newVersionString" -ForegroundColor Green

# Write JSON atomically
$tempFile = "$VersionFile.tmp"

$version | ConvertTo-Json -Depth 4 | Set-Content -Path $tempFile -Encoding UTF8
Move-Item -Path $tempFile -Destination $VersionFile -Force

Write-Host "[OK] version.json updated." -ForegroundColor Green
Write-Host "[*] Message: $Message"
