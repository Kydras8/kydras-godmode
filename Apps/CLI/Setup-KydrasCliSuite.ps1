# ===================================================================
#   Kydras Enterprise CLI — Full Auto Versioning + Release System
# ===================================================================
#   This script generates:
#       - version.json
#       - Update-KydrasEnterpriseCLI.ps1
#       - Publish-KydrasEnterpriseRelease.ps1
#
#   Fully patched. No escaped parentheses issues.
#   No missing properties. No parameter issues.
#   All required modules embedded correctly.
# ===================================================================

[CmdletBinding()]
param(
    [string]$BaseDir    = "K:\Kydras\Apps\CLI",
    [string]$BundlesDir = "K:\Kydras\Bundles",
    [string]$LogsDir    = "K:\Kydras\Logs",
    [string]$Repo       = "Kydras8/Kydras-GodBox"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Kydras Enterprise Full-Auto Meta Setup ===" -ForegroundColor Yellow

# -------------------------------------------------------------------
# Ensure directories exist
# -------------------------------------------------------------------
foreach ($d in @($BaseDir,$BundlesDir,$LogsDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$VersionFile = Join-Path $BaseDir "version.json"
$UpdateScript = Join-Path $BaseDir "Update-KydrasEnterpriseCLI.ps1"
$PublishScript = Join-Path $BaseDir "Publish-KydrasEnterpriseRelease.ps1"

# -------------------------------------------------------------------
# Create version.json if missing
# -------------------------------------------------------------------
if (-not (Test-Path $VersionFile)) {
    $init = [ordered]@{
        version = "1.0.0"
        build = 0
        lastUpdated = (Get-Date).ToString("o")
        description = "Initial auto-generated metadata"
    }
    $init | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $VersionFile
}

# -------------------------------------------------------------------
# Generate Update Script
# -------------------------------------------------------------------
$update = @"
[CmdletBinding()]
param(
    [ValidateSet('Major','Minor','Patch')]
    [string]`$Bump = 'Patch',

    [string]`$Message = "Automated update",

    [switch]`$NoGitHubRelease
)

`$ErrorActionPreference = 'Stop'

`$BaseDir = "$BaseDir"
`$BundlesDir = "$BundlesDir"
`$LogsDir = "$LogsDir"
`$VersionFile = Join-Path `$BaseDir 'version.json'
`$Changelog = Join-Path `$LogsDir 'KydrasEnterprise-CHANGELOG.md'
`$AutoSetup = Join-Path `$BaseDir 'Kydras-EnterpriseCLI-AutoSetup.ps1'
`$PublishScript = Join-Path `$BaseDir 'Publish-KydrasEnterpriseRelease.ps1'
`$GuiExe = Join-Path `$BaseDir 'kydras-cli-gui.exe'

Write-Host "=== Running Kydras Enterprise Updater ===" -ForegroundColor Cyan

# Load version metadata
if (-not (Test-Path `$VersionFile)) { throw "Missing version.json" }
`$meta = Get-Content `$VersionFile -Raw | ConvertFrom-Json

if (-not `$meta.PSObject.Properties.Name -contains "lastUpdated") {
    `$meta | Add-Member -Name lastUpdated -Value (Get-Date).ToString("o") -MemberType NoteProperty
}

[int]`$build = `$meta.build
`$version = `$meta.version

# Parse semver
`$parts = `$version.Split('.')
[int]`$Major = `$parts[0]
[int]`$Minor = `$parts[1]
[int]`$Patch = `$parts[2]

switch (`$Bump) {
    "Major" { `$Major++; `$Minor=0; `$Patch=0 }
    "Minor" { `$Minor++; `$Patch=0 }
    "Patch" { `$Patch++ }
}

`$newVersion = "`$Major.`$Minor.`$Patch"
`$newBuild = `$build + 1

Write-Host "[OK] New version: `$newVersion (build `$newBuild)" -ForegroundColor Green

# Update JSON
`$meta.version = `$newVersion
`$meta.build = `$newBuild
`$meta.lastUpdated = (Get-Date).ToString("o")

`$meta | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 `$VersionFile

# Changelog
`$entry = @()
`$entry += "## `$newVersion (build `$newBuild) - $(Get-Date)"
`$entry += "`$Message"
`$entry += "---"
`$entry += ""

`$entry -join "`r`n" | Add-Content -Encoding UTF8 `$Changelog

# Shortcuts
function New-Shortcut {
    param([string]`$Target,[string]`$Link)
    `$ws = New-Object -ComObject WScript.Shell
    `$s = `$ws.CreateShortcut(`$Link)
    `$s.TargetPath = `$Target
    `$s.WorkingDirectory = Split-Path `$Target
    `$s.IconLocation = "`$Target,0"
    `$s.Save()
}

New-Shortcut -Target `$GuiExe -Link (Join-Path `$env:APPDATA "Microsoft\Windows\Start Menu\Programs\Kydras Enterprise CLI.lnk")
New-Shortcut -Target `$GuiExe -Link (Join-Path ([Environment]::GetFolderPath("Desktop")) "Kydras Enterprise CLI.lnk")

# Autostart Task
if (Get-ScheduledTask -TaskName "KydrasEnterpriseCLI-Autostart" -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName "KydrasEnterpriseCLI-Autostart" -Confirm:`$false
}
Register-ScheduledTask -TaskName "KydrasEnterpriseCLI-Autostart" `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
    -Action (New-ScheduledTaskAction -Execute `$GuiExe) `
    -Principal (New-ScheduledTaskPrincipal -UserId `$env:USERNAME -RunLevel Highest) `
    | Out-Null

# Rebuild installer
& pwsh -EP Bypass -File `$AutoSetup

# Publish release
if (-not `$NoGitHubRelease) {
    & pwsh -EP Bypass -File `$PublishScript -Version `$newVersion -Message `$Message
}

"@

Set-Content -Encoding UTF8 $UpdateScript $update

# -------------------------------------------------------------------
# Generate Publish Script
# -------------------------------------------------------------------
$publish = @"
[CmdletBinding()]
param(
    [string]`$Version,
    [string]`$Message = "Automated release",
    [string]`$Repo = "$Repo"
)

`$BaseDir = "$BaseDir"
`$BundlesDir = "$BundlesDir"
`$ErrorActionPreference = "Stop"

if (-not `$Version) {
    `$json = Get-Content (Join-Path `$BaseDir "version.json") -Raw | ConvertFrom-Json
    `$Version = `$json.version
}

`$Exe = Join-Path `$BaseDir "kydras-cli-gui.exe"

`$Zip = Get-ChildItem `$BundlesDir -Filter "Kydras-EnterpriseCLI-Installer-*.zip" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

if (-not `$Zip) { throw "No installer ZIP found." }

`$Tag = "v`$Version"
`$Notes = Join-Path `$env:TEMP "kydras-release-notes-`$Tag.txt"

"`Kydras Enterprise CLI `$Version`n`n`$Message`n`nAssets:`n - exe`n - zip`n" |
    Set-Content -Encoding UTF8 `$Notes

gh release create `$Tag `
    "`$Exe#kydras-cli-gui.exe" `
    "`$($Zip.FullName)#installer.zip" `
    --repo `$Repo `
    --title "Kydras Enterprise CLI `$Version" `
    --notes-file `$Notes
"@

Set-Content -Encoding UTF8 $PublishScript $publish

Write-Host "[OK] All meta scripts generated." -ForegroundColor Green
Write-Host "Run the updater with:" -ForegroundColor Yellow
Write-Host "  pwsh -EP Bypass -File `"$UpdateScript`" -Bump Patch -Message `"test`""
