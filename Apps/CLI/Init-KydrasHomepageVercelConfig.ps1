<#
    Init-KydrasHomepageVercelConfig.ps1

    Purpose:
      - Create or update vercel.json for kydras-homepage-site.
      - Make the repo plug-and-play with Vercel's GitHub integration.

    Target:
      K:\Kydras\Repos\kydras-homepage-site\vercel.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath     = 'K:\Kydras\Repos\kydras-homepage-site'
$VercelConfig = Join-Path $RepoPath 'vercel.json'

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: Repo path not found: $RepoPath"
    exit 1
}

# Backup existing vercel.json if present
if (Test-Path $VercelConfig) {
    $backupPath = "$VercelConfig.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    Copy-Item -Path $VercelConfig -Destination $backupPath -Force
    Write-Host "[OK] Existing vercel.json backed up to: $backupPath"
}

# Minimal Next.js/Vercel config
$json = @'
{
  "version": 2,
  "framework": "nextjs",
  "github": {
    "enabled": true,
    "autoJobCancelation": true
  }
}
'@

$json | Set-Content -Path $VercelConfig -Encoding UTF8

Write-Host "[OK] vercel.json written to: $VercelConfig"
Write-Host "Next: git add vercel.json && git commit && push."
