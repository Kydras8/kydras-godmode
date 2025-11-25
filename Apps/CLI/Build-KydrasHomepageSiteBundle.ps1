<#
    Build-KydrasHomepageSiteBundle.ps1

    Purpose:
      - Build the Next.js site in kydras-homepage-site.
      - Package the production artifacts into a timestamped bundle + ZIP.

    Output:
      Folder: K:\Kydras\Bundles\kydras-homepage-site_YYYYMMDD_HHMMSS\
      Zip:    K:\Kydras\Bundles\kydras-homepage-site_YYYYMMDD_HHMMSS.zip
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath    = 'K:\Kydras\Repos\kydras-homepage-site'
$BundlesRoot = 'K:\Kydras\Bundles'

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: Repo path not found: $RepoPath"
    exit 1
}

if (-not (Test-Path $BundlesRoot)) {
    New-Item -Path $BundlesRoot -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created bundles root: $BundlesRoot"
}

# Ensure npm is available
if (-not (Get-Command -Name 'npm' -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: npm command not found in PATH."
    Write-Host "Install Node.js / npm or fix PATH first."
    exit 1
}

$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$bundleName = "kydras-homepage-site_$timestamp"
$bundleDir  = Join-Path $BundlesRoot $bundleName
$zipPath    = Join-Path $BundlesRoot "$bundleName.zip"

Write-Host "[*] RepoPath   : $RepoPath"
Write-Host "[*] BundleDir  : $bundleDir"
Write-Host "[*] ZipPath    : $zipPath"

# 1) Build the site
Push-Location $RepoPath
try {
    Write-Host "[*] Running npm install ..."
    npm install 2>&1 | ForEach-Object { Write-Host "[npm install] $_" }

    Write-Host "[*] Running npm run build ..."
    npm run build 2>&1 | ForEach-Object { Write-Host "[npm run build] $_" }
}
catch {
    Write-Host "ERROR: Node build failed: $_"
    Pop-Location
    exit 1
}
finally {
    Pop-Location
}

# 2) Create bundle directory
New-Item -Path $bundleDir -ItemType Directory -Force | Out-Null

# 3) Copy relevant artifacts
$itemsToCopy = @(
    '.next',
    'public',
    'package.json',
    'package-lock.json',
    'next.config.js',
    'next.config.mjs',
    'next.config.cjs',
    'tsconfig.json',
    'jsconfig.json'
)

foreach ($item in $itemsToCopy) {
    $src = Join-Path $RepoPath $item
    if (Test-Path $src) {
        Write-Host "[*] Copying $item -> $bundleDir"
        if (Test-Path $src -PathType Container) {
            Copy-Item -Path $src -Destination $bundleDir -Recurse -Force
        }
        else {
            Copy-Item -Path $src -Destination $bundleDir -Force
        }
    }
}

# 4) Create ZIP archive
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

Write-Host "[*] Creating ZIP: $zipPath"
Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $zipPath

Write-Host "[OK] Bundle folder created at: $bundleDir"
Write-Host "[OK] Bundle ZIP created at:    $zipPath"
