#!/usr/bin/env pwsh
<#
    Fix-GitHubAuth.ps1
    - Clears GITHUB_TOKEN from Process/User/Machine scopes
    - Logs out GitHub CLI
    - Starts a clean GitHub login flow
    - Verifies API access
#>

Write-Host "=== Resetting GitHub CLI authentication ===" -ForegroundColor Cyan

# -----------------------------
# STEP 1 — Remove env variables
# -----------------------------
Write-Host "`n[1] Clearing GITHUB_TOKEN environment variables..." -ForegroundColor Yellow

# Remove from current process
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

# Remove from User and Machine scopes
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $null, "User")
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $null, "Machine")

Write-Host "[OK] Environment variable cleared." -ForegroundColor Green

# -----------------------------
# STEP 2 — Logout existing gh session
# -----------------------------
Write-Host "`n[2] Logging out GitHub CLI..." -ForegroundColor Yellow

try {
    gh auth logout --hostname github.com
    Write-Host "[OK] gh auth logout complete." -ForegroundColor Green
} catch {
    Write-Host "[WARN] gh auth logout reported an error (usually safe): $_" -ForegroundColor DarkYellow
}

# -----------------------------
# STEP 3 — Start clean login
# -----------------------------
Write-Host "`n[3] Starting clean GitHub authentication..." -ForegroundColor Yellow
Write-Host "Follow instructions in your browser:" -ForegroundColor Cyan
Write-Host "  - Choose: GitHub.com"
Write-Host "  - Auth method: Login with a web browser"
Write-Host "  - Allow permissions: repo, read:org, read:user, user:email, workflow" -ForegroundColor Yellow

gh auth login --hostname github.com

# -----------------------------
# STEP 4 — Verify API access
# -----------------------------
Write-Host "`n[4] Testing GitHub GraphQL API..." -ForegroundColor Yellow

try {
    $res = gh api graphql -f query='{ viewer { login } }'
    Write-Host "[SUCCESS] GitHub API authenticated." -ForegroundColor Green
    Write-Host "Response:"
    Write-Host $res
} catch {
    Write-Host "[ERROR] API test failed. Check scopes and try login again." -ForegroundColor Red
}

Write-Host "`n=== Fix-GitHubAuth.ps1 complete ===" -ForegroundColor Cyan
