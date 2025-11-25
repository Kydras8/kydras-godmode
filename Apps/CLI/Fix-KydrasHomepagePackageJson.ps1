<#
    Fix-KydrasHomepagePackageJson.ps1

    Purpose:
      - Repair malformed package.json in:
          K:\Kydras\Repos\kydras-homepage-site\package.json
      - Handle double-escaped JSON.
      - Validate via ConvertFrom-Json.
      - If repair fails, write a minimal valid fallback package.json.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath       = 'K:\Kydras\Repos\kydras-homepage-site'
$PackageJson    = Join-Path $RepoPath 'package.json'

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: Repo path not found: $RepoPath"
    exit 1
}

if (-not (Test-Path $PackageJson)) {
    Write-Host "ERROR: package.json not found at: $PackageJson"
    exit 1
}

# Backup original file
$backupPath = "$PackageJson.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
Copy-Item -Path $PackageJson -Destination $backupPath -Force
Write-Host "[OK] Backup created: $backupPath"

# Load raw file
$raw = Get-Content -Path $PackageJson -Raw

function Try-ParseJson {
    param([string]$JsonText)

    try {
        $obj = $JsonText | ConvertFrom-Json -ErrorAction Stop
        return ,$obj
    }
    catch {
        return $null
    }
}

# Try original
$parsed = Try-ParseJson $raw
if ($parsed) {
    Write-Host "[OK] package.json already valid. No repair needed."
    exit 0
}

Write-Host "[*] Attempting repair..."

# Remove outer quotes if present
$work = $raw.Trim()
if ($work.StartsWith('"') -and $work.EndsWith('"')) {
    Write-Host "[*] Stripping outer quotes..."
    $work = $work.Trim('"')
}

# Remove escaped quotes
$work = $work -replace '\\\"','"'

# Try parsing repaired JSON
$parsedFixed = Try-ParseJson $work
if ($parsedFixed) {
    Write-Host "[OK] Auto-repair succeeded. Writing cleaned JSON..."

    $cleanJson = $parsedFixed | ConvertTo-Json -Depth 10
    $cleanJson | Set-Content -Path $PackageJson -Encoding UTF8

    Write-Host "[OK] package.json repaired."
    exit 0
}

Write-Host "[!] Auto-repair failed. Writing minimal valid fallback package.json."

# Fallback minimal package.json (all single quotes, no nested quotes)
$defaultObj = [pscustomobject]@{
    name        = 'kydras-homepage-site'
    version     = '1.0.0'
    private     = $true
    description = 'Kydras Systems Inc. homepage site (placeholder package.json)'
    scripts     = @{
        build = 'echo TODO add real build pipeline'
        test  = 'echo No tests specified'
    }
    dependencies    = @{}
    devDependencies = @{}
}

$defaultJson = $defaultObj | ConvertTo-Json -Depth 5
$defaultJson | Set-Content -Path $PackageJson -Encoding UTF8

Write-Host "[OK] Minimal fallback package.json written."
Write-Host "[INFO] Original file backed up at: $backupPath"
