#requires -version 7.0
<#
.SYNOPSIS
  Kydras GODMODE Bootstrapper
.DESCRIPTION
  One‑shot setup for VS Code GODMODE, Forge CLI, Compliance Monitor Service,
  WSL mirroring, governance artifact exports, and CI/CD pipeline templates.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Say($msg) { Write-Host "[Kydras] $msg" }

# --- 1. Install Forge CLI + PM2 ---
Say "Installing Forge CLI + PM2..."
npm install -g kydras-forge-cli pm2

# --- 2. Compliance Monitor Service (Windows) ---
$svcDir = Join-Path $env:USERPROFILE "kydras-compliance-service"
if (-not (Test-Path $svcDir)) {
  Say "Cloning Compliance Monitor Service..."
  git clone https://github.com/Kydras8/kydras-compliance-service $svcDir
} else {
  Say "Updating Compliance Monitor Service..."
  cd $svcDir; git pull
}
cd $svcDir; npm install
pm2 start server.js --name "kydras-compliance"
pm2 save; pm2 startup | Out-Null

# --- 3. WSL Mirroring ---
Say "Configuring WSL distros..."
$distros = wsl.exe --list --quiet
foreach ($distro in $distros) {
  Say "→ $distro"
  wsl.exe -d $distro npm install -g kydras-forge-cli pm2
  $svcDirWSL = "/home/$env:USERNAME/kydras-compliance-service"
  wsl.exe -d $distro bash -c "
    if [ ! -d $svcDirWSL ]; then
      git clone https://github.com/Kydras8/kydras-compliance-service $svcDirWSL
    else
      cd $svcDirWSL && git pull
    fi
    cd $svcDirWSL
    npm install
    npx pm2 start server.js --name kydras-compliance
    npx pm2 save
  "
}

# --- 4. Governance Artifact Export Hook ---
$outDir = Join-Path $env:USERPROFILE "kydras-governance"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
Say "Adding governance export script..."
@'
param([string]$Profile="KYDRAS-CORE",[string]$Brand="Kydras Systems Inc.")
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$badges = Get-Content "$PSScriptRoot/doctor_report.json" -Raw | ConvertFrom-Json
$stats  = @{
  pass = ($badges | ? status -eq "PASS").Count
  warn = ($badges | ? status -eq "WARN").Count
  fail = ($badges | ? status -eq "FAIL").Count
  total= $badges.Count
}
($badges | ConvertTo-Json -Depth 6) | Set-Content "$env:USERPROFILE/kydras-governance/doctor_report_$ts.json"
(New-Object System.Text.StringBuilder).AppendLine("| Plugin | Status | Severity |").ToString() | Out-File "$env:USERPROFILE/kydras-governance/audit_table_$ts.md"
"<!DOCTYPE html><html><body><h1>$Brand</h1><p>PASS:$($stats.pass) WARN:$($stats.warn) FAIL:$($stats.fail)</p></body></html>" | Out-File "$env:USERPROFILE/kydras-governance/executive_dashboard_$ts.html"
'@ | Set-Content (Join-Path $outDir "export.ps1")

# --- 5. Sample doctor_report.json ---
$sample = @'
[
  { "plugin":"TerraformLint","status":"PASS","severity":"low","timestamp":"2025-11-08T12:00:00Z","message":"All Terraform files validated","remediation":"" },
  { "plugin":"KubernetesPolicy","status":"WARN","severity":"medium","timestamp":"2025-11-08T12:00:00Z","message":"Pod security policy missing","remediation":"Add PSP or PodSecurity admission" },
  { "plugin":"SecretsScan","status":"FAIL","severity":"high","timestamp":"2025-11-08T12:00:00Z","message":"Hardcoded secret found","remediation":"Move secret to vault" }
]
'@
$sample | Set-Content (Join-Path $svcDir "doctor_report.json")

# --- 6. Devcontainer Setup ---
Say "Creating .devcontainer..."
$devDir = Join-Path (Get-Location) ".devcontainer"
if (-not (Test-Path $devDir)) { New-Item -ItemType Directory -Force -Path $devDir | Out-Null }

@'
{
  "name": "Kydras GODMODE Dev Box",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "lts" },
    "ghcr.io/devcontainers/features/python:1": { "version": "3.11" },
    "ghcr.io/devcontainers/features/go:1": { "version": "1.22" },
    "ghcr.io/devcontainers/features/rust:1": { "version": "latest" }
  },
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "customizations": {
    "vscode": {
      "extensions": [
        "eamodio.gitlens","mhutchie.git-graph","streetsidesoftware.code-spell-checker",
        "PKief.material-icon-theme","zhuangtongfa.Material-theme","usernamehw.errorlens",
        "ms-vscode-remote.remote-wsl","ms-vscode-remote.remote-ssh","ms-vscode-remote.remote-containers",
        "dbaeumer.vscode-eslint","esbenp.prettier-vscode","bradlc.vscode-tailwindcss",
        "humao.rest-client","rangav.vscode-thunder-client","ms-python.python",
        "ms-toolsai.jupyter","ms-vscode.cpptools","ms-azuretools.vscode-docker",
        "redhat.vscode-yaml","hashicorp.terraform","ms-kubernetes-tools.vscode-kubernetes-tools",
        "GitHub.copilot","GitHub.copilot-chat","Continue.continue"
      ]
    }
  },
  "remoteUser": "vscode"
}
'@ | Set-Content (Join-Path $devDir "devcontainer.json")

@'
#!/usr/bin/env bash
set -e
echo "[Kydras] Installing Forge CLI..."
npm install -g kydras-forge-cli
echo "[Kydras] Starting Compliance Monitor Service..."
cd /workspace/kydras-compliance-service || git clone https://github.com/Kydras8/kydras-compliance-service /workspace/kydras-compliance-service && cd /workspace/kydras-compliance-service
npm install
npx pm2 start server.js --name kydras-compliance
npx pm2 save
echo "[Kydras] ✅ Dev box setup complete."
'@ | Set-Content (Join-Path $devDir "setup.sh")

# --- 7. CI/CD Templates ---
Say "Adding CI/CD templates..."
$ghDir = ".github/workflows"; if (-not (Test-Path $ghDir)) { New-Item -ItemType Directory -Force -Path $ghDir | Out-Null }
@'
name: Kydras Governance Pipeline
on: [push, pull_request]
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: PowerShell/actions-setup-pwsh@v2
      - run: pwsh ./C:/Scripts/kydras-compliance.ps1 -Command export
      - uses: actions/upload-artifact@v4
        with:
          name: governance-artifacts
          path: ~/kydras-governance/*
'@ | Set-Content (Join-Path $ghDir "kydras-ci.yml")

@'
stages: [compliance]
compliance:
  image: mcr.microsoft.com/powershell:latest
  stage: compliance
  script:
    - pwsh ./C:/Scripts/kydras-compliance.ps1 -Command export
    - mkdir -p governance
    - cp $HOME/kydras-governance/* governance/
  artifacts:
    paths: [governance/]
    expire_in: 7 days
'@ | Set-Content ".gitlab-ci.yml"

Say "✅ GODMODE bootstrap complete. Reopen in VS Code Dev Container and visit http://localhost:8080"
