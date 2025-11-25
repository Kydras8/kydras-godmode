<# 
    Setup-KydrasEnterprise-Meta.ps1

    One-shot generator for:
      - version.json (semantic version + build)
      - Update-KydrasEnterpriseCLI.ps1
      - Publish-KydrasEnterpriseRelease.ps1

    After running this:
      Use Update-KydrasEnterpriseCLI.ps1 to:
        - bump version (Major/Minor/Patch)
        - rebuild EXE + installer (via Kydras-EnterpriseCLI-AutoSetup.ps1)
        - append to changelog
        - ensure Start Menu + Desktop shortcuts
        - ensure Autostart scheduled task
        - optionally publish GitHub release via gh

    Defaults:
      - BaseDir    = K:\Kydras\Apps\CLI
      - BundlesDir = K:\Kydras\Bundles
      - LogsDir    = K:\Kydras\Logs
      - Default GitHub repo: Kydras8/Kydras-GodBox   (change if needed)
#>

[CmdletBinding()]
param(
    [string]$BaseDir    = 'K:\Kydras\Apps\CLI',
    [string]$BundlesDir = 'K:\Kydras\Bundles',
    [string]$LogsDir    = 'K:\Kydras\Logs',
    [string]$DefaultRepo = 'Kydras8/Kydras-GodBox'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Setup Kydras Enterprise Meta (versioning + release) ===" -ForegroundColor Yellow
Write-Host "BaseDir    : $BaseDir"    -ForegroundColor Cyan
Write-Host "BundlesDir : $BundlesDir" -ForegroundColor Cyan
Write-Host "LogsDir    : $LogsDir"    -ForegroundColor Cyan
Write-Host "GitHub Repo: $DefaultRepo" -ForegroundColor Cyan
Write-Host ""

foreach ($d in @($BaseDir, $BundlesDir, $LogsDir)) {
    if (-not (Test-Path $d)) {
        Write-Host "Creating directory: $d" -ForegroundColor DarkCyan
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$VersionFile       = Join-Path $BaseDir 'version.json'
$UpdateScriptPath  = Join-Path $BaseDir 'Update-KydrasEnterpriseCLI.ps1'
$PublishScriptPath = Join-Path $BaseDir 'Publish-KydrasEnterpriseRelease.ps1'

# --- 1) version.json ----------------------------------------------------
if (-not (Test-Path $VersionFile)) {
    Write-Host "[*] Creating initial version.json ..." -ForegroundColor DarkCyan

    $initial = [ordered]@{
        version      = "1.0.0"
        build        = 1
        lastUpdated  = (Get-Date).ToString("o")
        description  = "Initial Kydras Enterprise CLI versioning setup"
    }

    $initial | ConvertTo-Json -Depth 5 | Set-Content -Path $VersionFile -Encoding UTF8

    Write-Host "[OK] version.json created at $VersionFile" -ForegroundColor Green
}
else {
    Write-Host "[OK] version.json already exists, leaving as-is: $VersionFile" -ForegroundColor Green
}

# --- 2) Template: Update-KydrasEnterpriseCLI.ps1 -----------------------
$updateTemplate = @'
<# 
    Update-KydrasEnterpriseCLI.ps1

    Responsibilities:
      - Load and bump version.json (Semantic Version: Major.Minor.Patch)
      - Increment build number
      - Update lastUpdated timestamp
      - Append entry to KydrasEnterprise-CHANGELOG.md
      - Ensure Start Menu + Desktop shortcuts
      - Ensure Autostart Scheduled Task at user logon
      - Call Kydras-EnterpriseCLI-AutoSetup.ps1 to rebuild EXE + installer
      - Optionally invoke Publish-KydrasEnterpriseRelease.ps1 (GitHub release)

    Examples:

      # Bump patch, rebuild EXE + installer, update changelog, publish GitHub release
      pwsh -EP Bypass -File ".\Update-KydrasEnterpriseCLI.ps1" -Bump Patch -Message "Pipeline v3 polish"

      # Bump minor, rebuild only (no release)
      pwsh -EP Bypass -File ".\Update-KydrasEnterpriseCLI.ps1" -Bump Minor -Message "Minor feature update" -NoGitHubRelease
#>

[CmdletBinding()]
param(
    [ValidateSet('Major','Minor','Patch')]
    [string]$Bump = 'Patch',

    [string]$Message = "Automated update",

    [switch]$NoGitHubRelease
)

$ErrorActionPreference = 'Stop'

# Resolve base directories
$BaseDir    = Split-Path -Parent $PSCommandPath
$BundlesDir = '@@BUNDLESDIR@@'
$LogsDir    = '@@LOGSDIR@@'

$VersionFile = Join-Path $BaseDir 'version.json'
$Changelog   = Join-Path $LogsDir 'KydrasEnterprise-CHANGELOG.md'
$AutoSetup   = Join-Path $BaseDir 'Kydras-EnterpriseCLI-AutoSetup.ps1'
$PublishScript = Join-Path $BaseDir 'Publish-KydrasEnterpriseRelease.ps1'
$GuiExe      = Join-Path $BaseDir 'kydras-cli-gui.exe'

Write-Host "=== Kydras Enterprise CLI Updater ===" -ForegroundColor Yellow
Write-Host "BaseDir    : $BaseDir"    -ForegroundColor Cyan
Write-Host "BundlesDir : $BundlesDir" -ForegroundColor Cyan
Write-Host "LogsDir    : $LogsDir"    -ForegroundColor Cyan
Write-Host "VersionFile: $VersionFile" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $VersionFile)) {
    throw "version.json not found at $VersionFile"
}

# --- Load and bump version ---------------------------------------------
$raw = Get-Content -Path $VersionFile -Raw | ConvertFrom-Json

if (-not $raw.version) { throw "version.json missing 'version' field" }
if (-not $raw.build)   { $raw | Add-Member -Name build -Value 0 -MemberType NoteProperty }

$currentVersion = [string]$raw.version
$build          = [int]$raw.build

Write-Host "[*] Current version: $currentVersion (build $build)" -ForegroundColor DarkGray

# Parse SemVer
$parts = $currentVersion.Split('.')
if ($parts.Count -lt 3) {
    throw "version field must be in form Major.Minor.Patch, got: $currentVersion"
}

[int]$major = $parts[0]
[int]$minor = $parts[1]
[int]$patch = $parts[2]

switch ($Bump) {
    'Major' {
        $major++
        $minor = 0
        $patch = 0
    }
    'Minor' {
        $minor++
        $patch = 0
    }
    'Patch' {
        $patch++
    }
}

$newVersion = "{0}.{1}.{2}" -f $major, $minor, $patch
$newBuild   = $build + 1
$now        = Get-Date

Write-Host "[OK] New version: $newVersion (build $newBuild)" -ForegroundColor Green

# Update JSON object
$raw.version     = $newVersion
$raw.build       = $newBuild
$raw.lastUpdated = $now.ToString("o")

# Save version.json
$raw | ConvertTo-Json -Depth 5 | Set-Content -Path $VersionFile -Encoding UTF8
Write-Host "[OK] version.json updated." -ForegroundColor Green

# --- Append changelog entry --------------------------------------------
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

$changelogEntry = @()
$changelogEntry += "## $newVersion (build $newBuild) - $now"
$changelogEntry += ""
$changelogEntry += $Message
$changelogEntry += ""
$changelogEntry += "---"
$changelogEntry += ""

$changelogEntry -join "`r`n" | Add-Content -Path $Changelog -Encoding UTF8
Write-Host "[OK] Changelog updated: $Changelog" -ForegroundColor Green

# --- Ensure shortcuts (Desktop + Start Menu) ---------------------------
function New-Shortcut {
    param(
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [string]$Description = "Kydras Enterprise CLI"
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Warning "Target for shortcut does not exist: $TargetPath"
        return
    }

    $dir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath       = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
    $shortcut.WindowStyle      = 1
    $shortcut.IconLocation     = "$TargetPath,0"
    $shortcut.Description      = $Description
    $shortcut.Save()
}

# Start Menu shortcut
$startMenuDir  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$startShortcut = Join-Path $startMenuDir 'Kydras Enterprise CLI.lnk'

Write-Host "[*] Ensuring Start Menu shortcut: $startShortcut" -ForegroundColor DarkGray
New-Shortcut -TargetPath $GuiExe -ShortcutPath $startShortcut

# Desktop shortcut
$desktopDir      = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = Join-Path $desktopDir 'Kydras Enterprise CLI.lnk'

Write-Host "[*] Ensuring Desktop shortcut: $desktopShortcut" -ForegroundColor DarkGray
New-Shortcut -TargetPath $GuiExe -ShortcutPath $desktopShortcut

# --- Ensure Autostart Scheduled Task at logon --------------------------
function Ensure-AutostartTask {
    param(
        [string]$TaskName = 'KydrasEnterpriseCLI-Autostart',
        [string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        Write-Warning "Cannot create autostart task; EXE not found: $ExePath"
        return
    }

    Write-Host "[*] Ensuring Scheduled Task: $TaskName" -ForegroundColor DarkGray

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $action   = New-ScheduledTaskAction -Execute $ExePath
    $trigger  = New-ScheduledTaskTrigger -AtLogOn
    $principal= New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
    Write-Host "[OK] Autostart task registered: $TaskName" -ForegroundColor Green
}

Ensure-AutostartTask -ExePath $GuiExe

# --- Rebuild EXE + installer via AutoSetup -----------------------------
if (-not (Test-Path $AutoSetup)) {
    Write-Warning "Auto-setup script not found at: $AutoSetup. Skipping rebuild."
} else {
    Write-Host "[*] Running auto-setup to rebuild EXE + installer..." -ForegroundColor Cyan
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $AutoSetup

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Auto-setup exited with code $LASTEXITCODE."
    } else {
        Write-Host "[OK] Auto-setup completed successfully." -ForegroundColor Green
    }
}

# --- Optionally publish GitHub release ---------------------------------
if (-not $NoGitHubRelease) {
    if (Test-Path $PublishScript) {
        Write-Host "[*] Publishing GitHub release for version $newVersion ..." -ForegroundColor Cyan
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PublishScript -Version $newVersion -Message $Message
        Write-Host "[OK] Release script invoked." -ForegroundColor Green
    } else {
        Write-Warning "Publish script not found at: $PublishScript"
    }
} else {
    Write-Host "[INFO] NoGitHubRelease flag set; skipping release publish." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Update complete: version $newVersion (build $newBuild)" -ForegroundColor Yellow
'@

# Apply directory placeholders
$updateContent = $updateTemplate.Replace('@@BUNDLESDIR@@', $BundlesDir).Replace('@@LOGSDIR@@', $LogsDir)
Set-Content -Path $UpdateScriptPath -Value $updateContent -Encoding UTF8
Write-Host "[OK] Update script written: $UpdateScriptPath" -ForegroundColor Green

# --- 3) Template: Publish-KydrasEnterpriseRelease.ps1 ------------------
$publishTemplate = @'
<# 
    Publish-KydrasEnterpriseRelease.ps1

    Creates a GitHub Release for the current Kydras Enterprise CLI version.

    Requirements:
      - GitHub CLI (gh) installed
      - gh auth status == logged in with appropriate permissions
      - version.json present
      - Latest installer ZIP in BundlesDir
      - EXE present in BaseDir

    Example:

      pwsh -EP Bypass -File ".\Publish-KydrasEnterpriseRelease.ps1" -Version 1.2.3 -Message "New pipeline features"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,

    [string]$Message = "Automated release",

    [string]$Repo = '@@DEFAULTREPO@@'
)

$ErrorActionPreference = 'Stop'

# Resolve base and bundles dirs
$BaseDir    = Split-Path -Parent $PSCommandPath
$BundlesDir = '@@BUNDLESDIR@@'

Write-Host "=== Publish Kydras Enterprise CLI Release ===" -ForegroundColor Yellow
Write-Host "Repo      : $Repo"       -ForegroundColor Cyan
Write-Host "BaseDir   : $BaseDir"    -ForegroundColor Cyan
Write-Host "BundlesDir: $BundlesDir" -ForegroundColor Cyan
Write-Host ""

# --- Ensure gh ---------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' not found. Install from https://cli.github.com/ and rerun."
}

try {
    gh auth status | Out-Null
} catch {
    throw "gh auth status failed. Run 'gh auth login' first."
}

# --- Resolve version ---------------------------------------------------
$VersionFile = Join-Path $BaseDir 'version.json'
if (-not $Version -and (Test-Path $VersionFile)) {
    $meta = Get-Content -Path $VersionFile -Raw | ConvertFrom-Json
    if ($meta.version) {
        $Version = [string]$meta.version
    }
}

if (-not $Version) {
    throw "Version not supplied and could not be read from version.json."
}

$tag   = "v$Version"
$title = "Kydras Enterprise CLI $Version"

# --- Locate EXE and latest installer ZIP -------------------------------
$ExePath = Join-Path $BaseDir 'kydras-cli-gui.exe'
if (-not (Test-Path $ExePath)) {
    throw "EXE not found at $ExePath"
}

$latestZip = Get-ChildItem -Path $BundlesDir -Filter 'Kydras-EnterpriseCLI-Installer-*.zip' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

if (-not $latestZip) {
    throw "No installer ZIPs found under $BundlesDir"
}

Write-Host "[OK] Using EXE   : $ExePath" -ForegroundColor Green
Write-Host "[OK] Using ZIP   : $($latestZip.FullName)" -ForegroundColor Green
Write-Host "[*] Release tag  : $tag" -ForegroundColor Cyan
Write-Host ""

# --- Build notes file --------------------------------------------------
$notesPath = Join-Path $env:TEMP ("kydras-release-notes-$tag.txt")

$notes = @()
$notes += "Kydras Enterprise CLI $Version"
$notes += ""
$notes += $Message
$notes += ""
$notes += "Assets:"
$notes += " - kydras-cli-gui.exe"
$notes += " - $([System.IO.Path]::GetFileName($latestZip.FullName))"
$notes += ""
$notesText = $notes -join "`r`n"

Set-Content -Path $notesPath -Value $notesText -Encoding UTF8

Write-Host "[*] Creating GitHub release on $Repo with tag $tag ..." -ForegroundColor Cyan

# gh release create <tag> <files...> --repo <owner/repo> --notes-file <file> --title <title>
gh release create $tag `
    "$ExePath#Kydras Enterprise CLI.exe" `
    "$($latestZip.FullName)#Kydras Enterprise CLI Installer ZIP" `
    --repo $Repo `
    --notes-file $notesPath `
    --title "$title"

Write-Host ""
Write-Host "[OK] GitHub release created: $tag" -ForegroundColor Green
'@

$publishContent = $publishTemplate.Replace('@@DEFAULTREPO@@', $DefaultRepo).Replace('@@BUNDLESDIR@@', $BundlesDir)
Set-Content -Path $PublishScriptPath -Value $publishContent -Encoding UTF8
Write-Host "[OK] Publish script written: $PublishScriptPath" -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Yellow
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1) To bump version and rebuild: " -NoNewline -ForegroundColor Yellow
Write-Host "pwsh -EP Bypass -File `"$UpdateScriptPath`" -Bump Patch -Message `"Your message`"" -ForegroundColor Cyan
Write-Host "  2) To publish a release only: " -NoNewline -ForegroundColor Yellow
Write-Host "pwsh -EP Bypass -File `"$PublishScriptPath`" -Version X.Y.Z -Message `"Release notes`"" -ForegroundColor Cyan
