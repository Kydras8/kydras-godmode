<#
    Patch-KydrasHomepageSite-Gitignore.ps1

    Purpose:
      - Ensure kydras-homepage-site has a proper .gitignore.
      - Ignore Node/Next build artifacts, env files, backup files.

    Target:
      K:\Kydras\Repos\kydras-homepage-site\.gitignore
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath      = 'K:\Kydras\Repos\kydras-homepage-site'
$GitignorePath = Join-Path $RepoPath '.gitignore'

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: Repo path not found: $RepoPath"
    exit 1
}

# Backup existing .gitignore (if any)
if (Test-Path $GitignorePath) {
    $backupPath = "$GitignorePath.bak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    Copy-Item -Path $GitignorePath -Destination $backupPath -Force
    Write-Host "[OK] Existing .gitignore backed up to: $backupPath"
}

# New .gitignore content for Next.js / Node
$gitignoreContent = @'
# Node / npm
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-lock.yaml

# Next.js build output
.next/
out/

# Logs
logs/
*.log

# Env files
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Editor / IDE
.vscode/
.idea/
*.swp

# OS cruft
.DS_Store
Thumbs.db

# Local backups (from repair scripts)
package.json.bak*
'@

$gitignoreContent | Set-Content -Path $GitignorePath -Encoding UTF8

Write-Host "[OK] .gitignore written to: $GitignorePath"
Write-Host "You should now commit .gitignore, package-lock.json, and cleaned package.json."
