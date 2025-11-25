#!/usr/bin/env pwsh
<#
    Kydras-RepoManagerGUI.ps1
    - Simple WinForms GUI wrapper for Kydras Repo Manager actions
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (\K:\Kydras\Apps\CLI\Kydras-RepoSystem-Upgrade-v3.ps1) {
    \ = Split-Path -Parent \K:\Kydras\Apps\CLI\Kydras-RepoSystem-Upgrade-v3.ps1
} else {
    \ = (Get-Location).Path
}

\    = Join-Path \ "Clone-All-KydrasRepos.ps1"
\ = Join-Path \ "Run-KydrasFullPipeline.ps1"
\     = Join-Path \ "Kydras-RepoIntegrityScan.ps1"
\     = Join-Path \ "Kydras-RepoAutoHeal.ps1"

function Start-ExternalScript([string]\) {
    if (-not (Test-Path \)) {
        [System.Windows.Forms.MessageBox]::Show("Script not found:

\","Missing Script",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File "\""
}

\              = New-Object System.Windows.Forms.Form
\.Text         = "Kydras Repo Manager"
\.Size         = New-Object System.Drawing.Size(420,260)
\.StartPosition= "CenterScreen"

\ = New-Object System.Drawing.Font("Segoe UI",10)

\          = New-Object System.Windows.Forms.Button
\.Text     = "Clone / Update All Repos"
\.Size     = New-Object System.Drawing.Size(360,35)
\.Location = New-Object System.Drawing.Point(20,20)
\.Font     = \
\.Add_Click({ Start-ExternalScript \ })

\          = New-Object System.Windows.Forms.Button
\.Text     = "Run Full Pipeline"
\.Size     = New-Object System.Drawing.Size(360,35)
\.Location = New-Object System.Drawing.Point(20,65)
\.Font     = \
\.Add_Click({ Start-ExternalScript \ })

\          = New-Object System.Windows.Forms.Button
\.Text     = "Scan Repo Health"
\.Size     = New-Object System.Drawing.Size(360,35)
\.Location = New-Object System.Drawing.Point(20,110)
\.Font     = \
\.Add_Click({ Start-ExternalScript \ })

\          = New-Object System.Windows.Forms.Button
\.Text     = "Auto-Heal Repos"
\.Size     = New-Object System.Drawing.Size(360,35)
\.Location = New-Object System.Drawing.Point(20,155)
\.Font     = \
\.Add_Click({ Start-ExternalScript \ })

\          = New-Object System.Windows.Forms.Button
\.Text     = "Close"
\.Size     = New-Object System.Drawing.Size(360,30)
\.Location = New-Object System.Drawing.Point(20,200)
\.Font     = \
\.Add_Click({ \.Close() })

\.Controls.AddRange(@(\,\,\,\,\))

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run(\)
