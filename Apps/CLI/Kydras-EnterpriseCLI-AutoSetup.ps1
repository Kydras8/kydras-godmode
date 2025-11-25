<# 
    Kydras-EnterpriseCLI-AutoSetup.ps1

    One-shot automation to:
      - Build Kydras CLI GUI EXE from Kydras-CLI-GUI.ps1 using ps2exe
      - Create a Start Menu shortcut for the EXE
      - Attempt to pin the EXE to the taskbar
      - Build a distributable ZIP "installer" with a bootstrap script

    Assumptions:
      - Base CLI directory: K:\Kydras\Apps\CLI
      - GUI script:        Kydras-CLI-GUI.ps1
      - Output EXE:        kydras-cli-gui.exe
      - Bundles:           K:\Kydras\Bundles
      - Logs:              K:\Kydras\Logs
#>

[CmdletBinding()]
param(
    [string]$BaseDir    = 'K:\Kydras\Apps\CLI',
    [string]$BundlesDir = 'K:\Kydras\Bundles',
    [string]$LogsDir    = 'K:\Kydras\Logs'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Kydras Enterprise CLI Auto Setup ===" -ForegroundColor Yellow
Write-Host "BaseDir    : $BaseDir"    -ForegroundColor Cyan
Write-Host "BundlesDir : $BundlesDir" -ForegroundColor Cyan
Write-Host "LogsDir    : $LogsDir"    -ForegroundColor Cyan
Write-Host ""

# --- Ensure core directories exist -------------------------------------
foreach ($dir in @($BaseDir, $BundlesDir, $LogsDir)) {
    if (-not (Test-Path $dir)) {
        Write-Host "Creating directory: $dir" -ForegroundColor DarkCyan
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Core paths --------------------------------------------------------
$GuiScript  = Join-Path $BaseDir 'Kydras-CLI-GUI.ps1'
$GuiExe     = Join-Path $BaseDir 'kydras-cli-gui.exe'
$ShortcutName = 'Kydras Enterprise CLI.lnk'
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$StartMenuShortcut = Join-Path $StartMenuDir $ShortcutName

# --- Sanity checks -----------------------------------------------------
if (-not (Test-Path $GuiScript)) {
    throw "GUI script not found at: $GuiScript. Make sure Kydras-CLI-GUI.ps1 exists."
}

Write-Host "[OK] Found GUI script: $GuiScript" -ForegroundColor Green

# --- Helper: Ensure ps2exe is available --------------------------------
function Ensure-Ps2ExeModule {
    Write-Host "[*] Checking for ps2exe module..." -ForegroundColor DarkGray
    try {
        Import-Module ps2exe -ErrorAction Stop
        Write-Host "[OK] ps2exe module loaded." -ForegroundColor Green
    }
    catch {
        Write-Warning "ps2exe not found. Attempting to install (CurrentUser)..."
        try {
            Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
            Import-Module ps2exe -ErrorAction Stop
            Write-Host "[OK] ps2exe installed and loaded." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install/load ps2exe. Install manually with:
  Install-Module ps2exe -Scope CurrentUser -Force
Then re-run this script."
            throw
        }
    }
}

# --- Helper: Create Start Menu shortcut --------------------------------
function New-StartMenuShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [string]$Description = "Kydras Enterprise CLI"
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Error "Cannot create shortcut; target does not exist: $TargetPath"
        return
    }

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $shortcutDir)) {
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
    }

    Write-Host "[*] Creating Start Menu shortcut at: $ShortcutPath" -ForegroundColor DarkCyan

    $wshShell   = New-Object -ComObject WScript.Shell
    $shortcut   = $wshShell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath       = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    $shortcut.WindowStyle      = 1
    $shortcut.IconLocation     = "$TargetPath,0"
    $shortcut.Description      = $Description
    $shortcut.Save()

    Write-Host "[OK] Start Menu shortcut created." -ForegroundColor Green
}

# --- Helper: Pin to taskbar (best-effort, may silently fail) -----------
function Pin-AppToTaskbar {
    param(
        [Parameter(Mandatory=$true)][string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        Write-Error "Cannot pin; EXE does not exist: $ExePath"
        return
    }

    Write-Host "[*] Attempting to pin to taskbar (best-effort)..." -ForegroundColor DarkGray

    try {
        $shell  = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path $ExePath))
        $item   = $folder.ParseName((Split-Path $ExePath -Leaf))

        if (-not $item) {
            Write-Warning "Shell item lookup failed for: $ExePath"
            return
        }

        $verbs = $item.Verbs()
        $pinVerb = $null

        foreach ($v in $verbs) {
            $name = $v.Name.Replace('&','')
            # Try to find "Pin to taskbar" verb (English UI). This may not work on other locales.
            if ($name -match 'Pin to taskbar') {
                $pinVerb = $v
                break
            }
        }

        if ($pinVerb) {
            $pinVerb.DoIt()
            Write-Host "[OK] Pin to taskbar invoked (if not already pinned)." -ForegroundColor Green
        } else {
            Write-Warning "No 'Pin to taskbar' verb found. (Already pinned or non-English Windows)"
        }
    }
    catch {
        Write-Warning "Pin to taskbar failed: $_"
    }
}

# --- 1) Ensure ps2exe is available -------------------------------------
Ensure-Ps2ExeModule

# --- 2) Build / Rebuild EXE --------------------------------------------
Write-Host "[*] Building GUI EXE from: $GuiScript" -ForegroundColor Cyan
Write-Host "    -> Output: $GuiExe" -ForegroundColor Cyan

if (Test-Path $GuiExe) {
    Write-Host "    Existing EXE found; removing before rebuild..." -ForegroundColor DarkGray
    Remove-Item -Path $GuiExe -Force
}

Invoke-ps2exe -inputFile $GuiScript `
              -outputFile $GuiExe `
              -noConsole `
              -x64 `
              -title "Kydras Enterprise CLI" `
              -company "Kydras Systems Inc." `
              -product "Kydras Enterprise CLI GUI" `
              -description "Kydras black-gold enterprise control panel" `
              -iconFile $null

if (-not (Test-Path $GuiExe)) {
    throw "Failed to build EXE; expected at: $GuiExe"
}

Write-Host "[OK] Built EXE: $GuiExe" -ForegroundColor Green

# --- 3) Create Start Menu shortcut -------------------------------------
New-StartMenuShortcut -TargetPath $GuiExe -ShortcutPath $StartMenuShortcut

# --- 4) Attempt to pin EXE to taskbar ----------------------------------
Pin-AppToTaskbar -ExePath $GuiExe

# --- 5) Build distribution ZIP with installer --------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$distRoot  = Join-Path $BundlesDir ("Kydras-EnterpriseCLI-Installer-$timestamp")
$payload   = Join-Path $distRoot 'payload'

Write-Host ""
Write-Host "[*] Building distribution folder at: $distRoot" -ForegroundColor Cyan

if (Test-Path $distRoot) {
    Remove-Item -Path $distRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $distRoot  | Out-Null
New-Item -ItemType Directory -Path $payload   | Out-Null

# Copy payload: EXE + all PS1 scripts in BaseDir
Write-Host "[*] Copying payload files..." -ForegroundColor DarkGray
Copy-Item -Path (Join-Path $BaseDir '*.ps1') -Destination $payload -Force -ErrorAction SilentlyContinue
Copy-Item -Path $GuiExe -Destination $payload -Force

# Optional: copy config directory if it exists
$configDir = Join-Path $BaseDir 'config'
if (Test-Path $configDir) {
    Copy-Item -Path $configDir -Destination $payload -Recurse -Force
}

# --- Create installer script inside distRoot ---------------------------
$installerScriptPath = Join-Path $distRoot 'Install-KydrasEnterpriseCLI.ps1'

$installerContent = @'
<# 
    Install-KydrasEnterpriseCLI.ps1

    Simple bootstrap installer for Kydras Enterprise CLI.

    Actions:
      - Copy payload files to C:\Kydras\Apps\CLI
      - Create Start Menu shortcut
      - Attempt to pin EXE to taskbar (best-effort)
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Kydras\Apps\CLI'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Kydras Enterprise CLI Installer ===" -ForegroundColor Yellow
Write-Host "InstallDir : $InstallDir" -ForegroundColor Cyan

$payloadDir = Join-Path $PSScriptRoot 'payload'

if (-not (Test-Path $payloadDir)) {
    throw "Payload directory not found: $payloadDir"
}

# 1) Ensure target directory exists
if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating install directory: $InstallDir" -ForegroundColor DarkCyan
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 2) Copy payload
Write-Host "Copying files from payload to install directory..." -ForegroundColor DarkCyan
Copy-Item -Path (Join-Path $payloadDir '*') -Destination $InstallDir -Recurse -Force

# 3) Locate EXE
$exePath = Join-Path $InstallDir 'kydras-cli-gui.exe'
if (-not (Test-Path $exePath)) {
    Write-Warning "EXE not found after copy: $exePath"
} else {
    Write-Host "[OK] Installed EXE: $exePath" -ForegroundColor Green
}

# 4) Create Start Menu shortcut (user-level)
$shortcutName = 'Kydras Enterprise CLI.lnk'
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuDir $shortcutName

function New-StartMenuShortcutLocal {
    param(
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [string]$Description = "Kydras Enterprise CLI"
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Error "Cannot create shortcut; target does not exist: $TargetPath"
        return
    }

    $dir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $wshShell   = New-Object -ComObject WScript.Shell
    $shortcut   = $wshShell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath       = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    $shortcut.WindowStyle      = 1
    $shortcut.IconLocation     = "$TargetPath,0"
    $shortcut.Description      = $Description
    $shortcut.Save()
}

if (Test-Path $exePath) {
    Write-Host "Creating Start Menu shortcut at: $shortcutPath" -ForegroundColor DarkCyan
    New-StartMenuShortcutLocal -TargetPath $exePath -ShortcutPath $shortcutPath
    Write-Host "[OK] Shortcut created." -ForegroundColor Green
}

# 5) Attempt to pin to taskbar (best-effort)
function Pin-AppToTaskbarLocal {
    param(
        [Parameter(Mandatory=$true)][string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        Write-Error "Cannot pin; EXE does not exist: $ExePath"
        return
    }

    Write-Host "Attempting to pin to taskbar (best-effort)..." -ForegroundColor DarkGray

    try {
        $shell  = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path $ExePath))
        $item   = $folder.ParseName((Split-Path $ExePath -Leaf))

        if (-not $item) {
            Write-Warning "Shell item lookup failed for: $ExePath"
            return
        }

        $verbs = $item.Verbs()
        $pinVerb = $null

        foreach ($v in $verbs) {
            $name = $v.Name.Replace('&','')
            if ($name -match 'Pin to taskbar') {
                $pinVerb = $v
                break
            }
        }

        if ($pinVerb) {
            $pinVerb.DoIt()
            Write-Host "[OK] Pin to taskbar invoked (if not already pinned)." -ForegroundColor Green
        } else {
            Write-Warning "No 'Pin to taskbar' verb found. (Already pinned or non-English Windows)"
        }
    }
    catch {
        Write-Warning "Pin to taskbar failed: $_"
    }
}

if (Test-Path $exePath) {
    Pin-AppToTaskbarLocal -ExePath $exePath
}

Write-Host ""
Write-Host "Kydras Enterprise CLI installation complete." -ForegroundColor Yellow
'@

Set-Content -Path $installerScriptPath -Value $installerContent -Encoding UTF8

# --- 6) Compress distribution to ZIP -----------------------------------
$zipName = "Kydras-EnterpriseCLI-Installer-$timestamp.zip"
$zipPath = Join-Path $BundlesDir $zipName

if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

Write-Host "[*] Creating ZIP: $zipPath" -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $distRoot '*') -DestinationPath $zipPath

Write-Host ""
Write-Host "[OK] Distribution ZIP created:" -ForegroundColor Green
Write-Host "     $zipPath" -ForegroundColor Green

Write-Host ""
Write-Host "All done." -ForegroundColor Yellow
Write-Host "You can share the ZIP; on another machine, extract and run:" -ForegroundColor Yellow
Write-Host "  Install-KydrasEnterpriseCLI.ps1" -ForegroundColor Yellow
