<# 
    Kydras-CLI-GUI.ps1 

    Enterprise-grade WinForms GUI with:
      - Black/Gold theme
      - Eye of Kydras watermark
      - Admin Token status
      - Status console panel (log output)
      - Animated progress for Pipeline & Bundle
      - Buttons for: 
          * Admin Terminal
          * WSL (Kali)
          * Repo Manager
          * Clone All Repos
          * Run Full Pipeline v3
          * Build Enterprise Bundle ZIP
          * Open Logs Folder
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- BRAND CONFIG ------------------------------------------------------
$LogoPath = 'K:\Kydras\Assets\kydras-logo.png'

$ColorBg        = [System.Drawing.Color]::FromArgb(12,12,16)
$ColorPanel     = [System.Drawing.Color]::FromArgb(24,24,32)
$ColorAccent    = [System.Drawing.Color]::FromArgb(212,175,55)
$ColorAccentDim = [System.Drawing.Color]::FromArgb(160,133,40)
$ColorText      = [System.Drawing.Color]::WhiteSmoke
$ColorTextSoft  = [System.Drawing.Color]::Gainsboro

# --- PATHS -------------------------------------------------------------
# Resolve script directory in a way that works for both .ps1 and compiled EXE
if ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
elseif ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
}
else {
    # Fallback: current directory
    $ScriptDir = (Get-Location).Path
}

$RepoManagerScript  = Join-Path $ScriptDir 'Kydras-RepoManager.ps1'
$CloneScript        = Join-Path $ScriptDir 'Clone-All-KydrasRepos.ps1'
$PipelineScript     = Join-Path $ScriptDir 'Run-KydrasFullPipeline.ps1'
$BundleScript       = Join-Path $ScriptDir 'Build-KydrasEnterpriseBundle.ps1'
$LogsRoot           = 'K:\Kydras\Logs'

# Track running background tasks
$script:RunningTasks = @{}

# --- HELPERS -----------------------------------------------------------
function Test-IsAdmin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = New-Object Security.Principal.WindowsPrincipal($id)
    return $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Message([string]$text, [string]$title = "Kydras CLI GUI") {
    [System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', 'Information') | Out-Null
}

# --- FORM --------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Kydras Enterprise CLI"
$form.Size            = New-Object System.Drawing.Size(580,520)
$form.StartPosition   = "CenterScreen"
$form.Topmost         = $true
$form.BackColor       = $ColorBg
$form.ForeColor       = $ColorText
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox     = $false

$fontTitle   = New-Object System.Drawing.Font("Segoe UI",13,[System.Drawing.FontStyle]::Bold)
$fontSub     = New-Object System.Drawing.Font("Segoe UI",9)
$fontBtn     = New-Object System.Drawing.Font("Segoe UI",10)
$fontFooter  = New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Italic)
$fontConsole = New-Object System.Drawing.Font("Consolas",8.5)

# Title
$labelTitle = New-Object System.Windows.Forms.Label
$labelTitle.Text      = "KYDRAS ENTERPRISE CONTROL PANEL"
$labelTitle.Font      = $fontTitle
$labelTitle.ForeColor = $ColorAccent
$labelTitle.AutoSize  = $true
$labelTitle.Location  = New-Object System.Drawing.Point(20,18)
$form.Controls.Add($labelTitle)

# Subtitle
$labelSub = New-Object System.Windows.Forms.Label
$labelSub.Text      = "Automated repo, pipeline, and bundle orchestration"
$labelSub.Font      = $fontSub
$labelSub.ForeColor = $ColorTextSoft
$labelSub.AutoSize  = $true
$labelSub.Location  = New-Object System.Drawing.Point(22,46)
$form.Controls.Add($labelSub)

# Admin Token
$labelAdmin = New-Object System.Windows.Forms.Label
$labelAdmin.Font     = $fontSub
$labelAdmin.AutoSize = $true
$labelAdmin.Location = New-Object System.Drawing.Point(22,68)

if (Test-IsAdmin) {
    $labelAdmin.Text      = "Admin Token: TRUE (full elevation)"
    $labelAdmin.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    $labelAdmin.Text      = "Admin Token: FALSE (run as Administrator)"
    $labelAdmin.ForeColor = [System.Drawing.Color]::IndianRed
}
$form.Controls.Add($labelAdmin)

# --- WATERMARK (logo) --------------------------------------------------
if (Test-Path $LogoPath) {
    try {
        $logo = [System.Drawing.Image]::FromFile($LogoPath)

        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image    = $logo
        $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pic.Size     = New-Object System.Drawing.Size(96,96)

        # top-right area
        $pic.Location = New-Object System.Drawing.Point(580 - 96 - 30, 12)  # X ~454, Y 12
        $pic.Anchor   = [System.Windows.Forms.AnchorStyles]::Top `
                        -bor [System.Windows.Forms.AnchorStyles]::Right

        $form.Controls.Add($pic)
    } catch {
        # ignore logo load failures
    }
}

# --- PROGRESS BAR (animated) -------------------------------------------
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size     = New-Object System.Drawing.Size(520,16)
$progress.Location = New-Object System.Drawing.Point(22,92)
$progress.Style    = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progress.MarqueeAnimationSpeed = 30
$progress.Visible  = $false
$form.Controls.Add($progress)

# --- STATUS CONSOLE ----------------------------------------------------
# Place near the bottom; fixed coordinates to avoid math bugs
$consoleHeight = 110
$consoleY      = 360

$console = New-Object System.Windows.Forms.RichTextBox
$console.Font        = $fontConsole
$console.BackColor   = $ColorBg
$console.ForeColor   = $ColorTextSoft
$console.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$console.ReadOnly    = $true
$console.Multiline   = $true
$console.ScrollBars  = "Vertical"
$console.Size        = New-Object System.Drawing.Size(520,$consoleHeight)
$console.Location    = New-Object System.Drawing.Point(22,$consoleY)
$console.Anchor      = [System.Windows.Forms.AnchorStyles]::Left `
                       -bor [System.Windows.Forms.AnchorStyles]::Right `
                       -bor [System.Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($console)

function Write-Console([string]$message) {
    if (-not $console) { return }
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $message
    $console.AppendText($line + [Environment]::NewLine)
    $console.ScrollToCaret()
}

# --- FOOTER ------------------------------------------------------------
$footer = New-Object System.Windows.Forms.Label
$footer.Text      = "KYDRAS • NOTHING IS OFF LIMITS"
$footer.Font      = $fontFooter
$footer.ForeColor = $ColorAccentDim
$footer.AutoSize  = $true
# fixed Y so we don't do ClientSize math
$footer.Location  = New-Object System.Drawing.Point(22, 480)
$footer.Anchor    = [System.Windows.Forms.AnchorStyles]::Left `
                    -bor [System.Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($footer)

# --- BUTTONS -----------------------------------------------------------
$yBase = 120
$yStep = 36  # 7 buttons: 0..6 → last at 120 + 6*36 = 336 (just above console)

function New-Button([string]$text, [int]$rowIndex, [ScriptBlock]$onClick) {
    $btn        = New-Object System.Windows.Forms.Button
    $btn.Text   = $text
    $btn.Font   = $fontBtn
    $btn.Size   = New-Object System.Drawing.Size(520,34)

    $y = $yBase + ($rowIndex * $yStep)
    $btn.Location = New-Object System.Drawing.Point(22,$y)

    # theme styling
    $btn.BackColor = $ColorPanel
    $btn.ForeColor = $ColorAccent
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = $ColorAccentDim
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(32,32,44)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(40,40,56)

    $btn.Add_Click($onClick)
    $form.Controls.Add($btn)
    return $btn
}

# --- TRACKED TASK LAUNCHER ---------------------------------------------
function Start-TrackedTask {
    param(
        [string]$Label,
        [string]$ScriptPath,
        [switch]$ShowProgress
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Console ("{0}: script not found at {1}" -f $Label, $ScriptPath)
        return
    }

    Write-Console ("{0}: starting ..." -f $Label)

    if ($ShowProgress) {
        $progress.Visible = $true
    }

    try {
        $argsArray = @(
            "-NoLogo","-NoProfile",
            "-ExecutionPolicy","Bypass",
            "-File",$ScriptPath
        )

        $proc = Start-Process -FilePath "pwsh" -ArgumentList $argsArray -PassThru
        $script:RunningTasks[$Label] = $proc
        Write-Console ("{0}: launched (PID {1})" -f $Label, $proc.Id)
    }
    catch {
        Write-Console ("{0}: failed to launch. {1}" -f $Label, $_)
        if ($ShowProgress) { $progress.Visible = $false }
    }
}

# Timer to watch for finished tasks
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $completed = @()
    foreach ($entry in $script:RunningTasks.GetEnumerator()) {
        $label = $entry.Key
        $proc  = $entry.Value
        if ($proc -and $proc.HasExited) {
            Write-Console ("{0}: completed (ExitCode {1})" -f $label, $proc.ExitCode)
            $completed += $label
        }
    }
    foreach ($label in $completed) {
        $script:RunningTasks.Remove($label)
    }
    if ($script:RunningTasks.Count -eq 0) {
        $progress.Visible = $false
    }
})
$timer.Start()

# --- BUTTON DEFINITIONS ------------------------------------------------

# 0 — Admin Terminal
New-Button "Open Admin Terminal (wt.exe)" 0 {
    try {
        Write-Console "Launching Windows Terminal as admin ..."
        Start-Process wt.exe -Verb RunAs | Out-Null
    } catch {
        Write-Console ("Admin terminal error: {0}" -f $_)
    }
} | Out-Null

# 1 — Kali WSL
New-Button "Open WSL (Kali)" 1 {
    try {
        Write-Console "Launching WSL (kali-linux) ..."
        Start-Process wsl.exe -ArgumentList "-d","kali-linux" | Out-Null
    } catch {
        Write-Console ("WSL error: {0}" -f $_)
    }
} | Out-Null

# 2 — Repo Manager
New-Button "Launch Repo Manager" 2 {
    Start-TrackedTask -Label "Repo Manager" `
        -ScriptPath $RepoManagerScript `
        -ShowProgress:$false
} | Out-Null

# 3 — Clone All
New-Button "Clone / Refresh All Repos" 3 {
    Start-TrackedTask -Label "Clone-All-Repos" `
        -ScriptPath $CloneScript `
        -ShowProgress:$false
} | Out-Null

# 4 — Pipeline
New-Button "Run Full Pipeline v3" 4 {
    Start-TrackedTask -Label "Full Pipeline v3" `
        -ScriptPath $PipelineScript `
        -ShowProgress
} | Out-Null

# 5 — Build Bundle
New-Button "Build Enterprise Bundle ZIP" 5 {
    Start-TrackedTask -Label "Enterprise Bundle" `
        -ScriptPath $BundleScript `
        -ShowProgress
} | Out-Null

# 6 — Logs
New-Button "Open Logs Folder" 6 {
    if (-not (Test-Path $LogsRoot)) {
        New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null
    }
    Write-Console ("Opening Logs folder at {0}" -f $LogsRoot)
    Start-Process explorer.exe $LogsRoot | Out-Null
} | Out-Null

# --- RUN DIALOG --------------------------------------------------------
Write-Console "Kydras CLI GUI loaded."
[void]$form.ShowDialog()

