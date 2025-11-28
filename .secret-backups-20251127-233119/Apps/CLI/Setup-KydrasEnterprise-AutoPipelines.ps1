[CmdletBinding()]
param(
    [string]$BaseDir    = "K:\Kydras\Apps\CLI",
    [string]$BundlesDir = "K:\Kydras\Bundles",
    [string]$RepoRoot   = "K:\Kydras\Repos\kydras-godmode"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Kydras Enterprise CLI Auto-Setup ===" -ForegroundColor Cyan
Write-Host "BaseDir    : $BaseDir"
Write-Host "BundlesDir : $BundlesDir"
Write-Host "RepoRoot   : $RepoRoot"
Write-Host ""

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Creating directory: $Path"
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Backup-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $backup = "$Path.bak-$ts"
        Write-Host "Backing up $Path -> $backup"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
    }
}

function Write-FileSafe {
    param(
        [string]$Path,
        [string]$Content
    )
    Backup-File -Path $Path
    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    Write-Host "Writing: $Path"
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# --- 1) Ensure main directories exist ---

Ensure-Directory -Path $BaseDir
Ensure-Directory -Path $BundlesDir

# --- 2) Initialize version.json and VERSION if missing ---

$versionJsonPath = Join-Path $BaseDir "version.json"
$versionTextPath = Join-Path $BaseDir "VERSION"

if (-not (Test-Path -LiteralPath $versionJsonPath) -and -not (Test-Path -LiteralPath $versionTextPath)) {
    Write-Host "No version files found. Initializing version 1.0.0 ..."
    $initial = @{ version = "1.0.0" } | ConvertTo-Json -Depth 2
    Set-Content -Path $versionJsonPath -Value $initial -Encoding UTF8
    Set-Content -Path $versionTextPath -Value "1.0.0`n" -Encoding UTF8
} else {
    Write-Host "Existing version files detected. Leaving them as-is."
}

# --- 3) Build-KydrasEnterpriseBundle.ps1 ---

$buildScriptPath = Join-Path $BaseDir "Build-KydrasEnterpriseBundle.ps1"
$buildScript = @'
[CmdletBinding()]
param(
    [string]$Version   = "0.0.0",
    [string]$OutputDir = $(Join-Path $PSScriptRoot "..\Bundles")
)

$ErrorActionPreference = "Stop"

Write-Host "=== Build-KydrasEnterpriseBundle ===" -ForegroundColor Cyan
Write-Host "Version   : $Version"
Write-Host "OutputDir : $OutputDir"
Write-Host ""

if (-not (Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    throw "Invoke-ps2exe not found. Please install module 'ps2exe' in PowerShell 7: Install-Module ps2exe -Scope CurrentUser"
}

$cliScript = Join-Path $PSScriptRoot "Kydras-EnterpriseCLI.ps1"
if (-not (Test-Path -LiteralPath $cliScript)) {
    throw "Main CLI script not found at: $cliScript"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    Write-Host "Creating OutputDir: $OutputDir"
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$exeName = "Kydras-EnterpriseCLI-$Version.exe"
$zipName = "Kydras-EnterpriseCLI-$Version.zip"

$exePath = Join-Path $OutputDir $exeName
$zipPath = Join-Path $OutputDir $zipName

Write-Host "Building EXE: $exePath"
Invoke-ps2exe -inputFile $cliScript `
              -outputFile $exePath `
              -noConsole `
              -x64 `
              -title "Kydras Enterprise CLI $Version"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "ps2exe did not produce output EXE at: $exePath"
}

Write-Host "Creating installer ZIP: $zipPath"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path $exePath, $cliScript -DestinationPath $zipPath -Force

Write-Host "Build complete."
Write-Host "EXE : $exePath"
Write-Host "ZIP : $zipPath"
'@

Write-FileSafe -Path $buildScriptPath -Content $buildScript

# --- 4) Update-KydrasEnterpriseCli.ps1 ---

$updateScriptPath = Join-Path $BaseDir "Update-KydrasEnterpriseCli.ps1"
$updateScript = @'
[CmdletBinding()]
param(
    [ValidateSet("major","minor","patch")]
    [string]$BumpType = "patch",

    [string]$ChangeSummary = "Automated build",

    [string]$BundlesDir = $(Join-Path $PSScriptRoot "..\Bundles"),

    [string]$LogRoot = $(Join-Path $PSScriptRoot "..\Logs\KydrasEnterpriseCli")
)

$ErrorActionPreference = "Stop"

Write-Host "=== Update-KydrasEnterpriseCli ===" -ForegroundColor Cyan
Write-Host "BumpType   : $BumpType"
Write-Host "BundlesDir : $BundlesDir"
Write-Host "LogRoot    : $LogRoot"
Write-Host ""

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Creating directory: $Path"
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-CurrentVersion {
    $baseDir = $PSScriptRoot
    $versionJsonPath = Join-Path $baseDir "version.json"
    $versionTextPath = Join-Path $baseDir "VERSION"

    if (Test-Path -LiteralPath $versionJsonPath) {
        $raw = Get-Content -LiteralPath $versionJsonPath -Raw
        try {
            $obj = $raw | ConvertFrom-Json
            if ($obj.version) {
                return [string]$obj.version
            }
        } catch {
            Write-Warning "Failed to parse version.json; falling back to VERSION file if present."
        }
    }

    if (Test-Path -LiteralPath $versionTextPath) {
        $txt = (Get-Content -LiteralPath $versionTextPath | Select-Object -First 1).Trim()
        if ($txt) { return $txt }
    }

    return "1.0.0"
}

function Get-NewVersion {
    param(
        [string]$OldVersion,
        [string]$BumpType
    )

    if (-not ($OldVersion -match '^\d+\.\d+\.\d+$')) {
        Write-Warning "Old version '$OldVersion' is not in x.y.z format. Resetting to 1.0.0."
        $OldVersion = "1.0.0"
    }

    $parts = $OldVersion.Split('.')
    [int]$major = $parts[0]
    [int]$minor = $parts[1]
    [int]$patch = $parts[2]

    switch ($BumpType) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "minor" {
            $minor++
            $patch = 0
        }
        "patch" {
            $patch++
        }
    }

    return "{0}.{1}.{2}" -f $major, $minor, $patch
}

function Save-Version {
    param(
        [string]$Version
    )

    $baseDir = $PSScriptRoot
    $versionJsonPath = Join-Path $baseDir "version.json"
    $versionTextPath = Join-Path $baseDir "VERSION"

    $obj = @{ version = $Version }
    $json = $obj | ConvertTo-Json -Depth 2

    Set-Content -Path $versionJsonPath -Value $json -Encoding UTF8
    Set-Content -Path $versionTextPath -Value ($Version + "`n") -Encoding UTF8
}

function New-KydrasShortcuts {
    param(
        [string]$CliScriptDir
    )

    $cliScript = Join-Path $CliScriptDir "Kydras-EnterpriseCLI.ps1"
    if (-not (Test-Path -LiteralPath $cliScript)) {
        Write-Warning "CLI script not found at: $cliScript. Skipping shortcut creation."
        return
    }

    $desktopPath        = [Environment]::GetFolderPath("Desktop")
    $startMenuPath      = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs"
    $startupPath        = [Environment]::GetFolderPath("Startup")
    $shortcutBaseName   = "Kydras Enterprise CLI"
    $pwshPath           = "pwsh.exe"

    $shell = New-Object -ComObject WScript.Shell

    $targets = @(
        @{ Name = "$shortcutBaseName.lnk";               Folder = $desktopPath      },
        @{ Name = "$shortcutBaseName.lnk";               Folder = $startMenuPath    },
        @{ Name = "$shortcutBaseName (AutoStart).lnk";   Folder = $startupPath      }
    )

    foreach ($t in $targets) {
        $folder = $t.Folder
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        $linkPath = Join-Path $folder $t.Name
        Write-Host "Creating shortcut: $linkPath"

        $shortcut = $shell.CreateShortcut($linkPath)
        $shortcut.TargetPath = $pwshPath
        $shortcut.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$cliScript`""
        $shortcut.WorkingDirectory = $CliScriptDir
        $shortcut.IconLocation     = "$pwshPath,0"
        $shortcut.Save()
    }
}

Ensure-Directory -Path $LogRoot
Ensure-Directory -Path $BundlesDir

$logFile = Join-Path $LogRoot ("Update-" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Write-Host "Logging to: $logFile"
Start-Transcript -Path $logFile -Force | Out-Null

try {
    $oldVersion = Get-CurrentVersion
    $newVersion = Get-NewVersion -OldVersion $oldVersion -BumpType $BumpType

    Write-Host "Old version : $oldVersion"
    Write-Host "New version : $newVersion"
    Write-Host ""

    Save-Version -Version $newVersion

    $buildScriptPath = Join-Path $PSScriptRoot "Build-KydrasEnterpriseBundle.ps1"
    if (-not (Test-Path -LiteralPath $buildScriptPath)) {
        throw "Build script not found at: $buildScriptPath"
    }

    Write-Host "Invoking build script..."
    & $buildScriptPath -Version $newVersion -OutputDir $BundlesDir

    Write-Host "Creating desktop/start menu/startup shortcuts..."
    New-KydrasShortcuts -CliScriptDir $PSScriptRoot

    Write-Host ""
    Write-Host "Update complete."
    Write-Host "Version      : $newVersion"
    Write-Host "BundlesDir   : $BundlesDir"
    Write-Host "ChangeSummary: $ChangeSummary"
}
finally {
    Stop-Transcript | Out-Null
}
'@

Write-FileSafe -Path $updateScriptPath -Content $updateScript

# --- 5) Run-KydrasFullPipeline.ps1 ---

$runPipelinePath = Join-Path $BaseDir "Run-KydrasFullPipeline.ps1"
$runPipelineScript = @'
[CmdletBinding()]
param(
    [ValidateSet("major","minor","patch")]
    [string]$BumpType = "patch",

    [string]$ChangeSummary = "Local full pipeline run",

    [string]$BundlesDir = "K:\Kydras\Bundles"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Run-KydrasFullPipeline ===" -ForegroundColor Cyan
Write-Host "BumpType   : $BumpType"
Write-Host "BundlesDir : $BundlesDir"
Write-Host ""

$updateScriptPath = Join-Path $PSScriptRoot "Update-KydrasEnterpriseCli.ps1"
if (-not (Test-Path -LiteralPath $updateScriptPath)) {
    throw "Update script not found at: $updateScriptPath"
}

& $updateScriptPath -BumpType $BumpType -ChangeSummary $ChangeSummary -BundlesDir $BundlesDir

Write-Host ""
Write-Host "Full pipeline completed."
'@

Write-FileSafe -Path $runPipelinePath -Content $runPipelineScript

# --- 6) Fix Kydras-RepoManager.ps1 bug if present ---

$repoManagerPath = Join-Path $BaseDir "Kydras-RepoManager.ps1"
if (Test-Path -LiteralPath $repoManagerPath) {
    Write-Host "Attempting to fix Kydras-RepoManager.ps1 'switch (\.ToUpper())' bug..."
    $text = Get-Content -LiteralPath $repoManagerPath -Raw
    $newText = $text.Replace('switch (\.ToUpper())','switch ($_.ToUpper())')
    if ($newText -ne $text) {
        Backup-File -Path $repoManagerPath
        Set-Content -Path $repoManagerPath -Value $newText -Encoding UTF8
        Write-Host "Kydras-RepoManager.ps1 patched."
    } else {
        Write-Host "No matching pattern found; RepoManager not modified."
    }
} else {
    Write-Host "Kydras-RepoManager.ps1 not found at $repoManagerPath, skipping fix."
}

# --- 7) GitHub Actions workflow for releases ---

$workflowDir  = Join-Path $RepoRoot ".github\workflows"
$workflowPath = Join-Path $workflowDir "kydras-enterprisecli-release.yml"

$workflowContent = @'
name: Kydras Enterprise CLI Release

on:
  push:
    tags:
      - "v*.*.*"

jobs:
  build-and-release:
    runs-on: windows-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build EXE and ZIP
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $repoRoot   = $env:GITHUB_WORKSPACE
          $scriptDir  = Join-Path $repoRoot "Apps/CLI"
          $bundlesDir = Join-Path $repoRoot "Bundles"

          if (-not (Test-Path -LiteralPath $bundlesDir)) {
            New-Item -ItemType Directory -Path $bundlesDir -Force | Out-Null
          }

          $updateScript = Join-Path $scriptDir "Update-KydrasEnterpriseCli.ps1"
          & $updateScript -BumpType "patch" -ChangeSummary "CI build" -BundlesDir $bundlesDir

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            Bundles/*.zip
            Bundles/*.exe
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
'@

Ensure-Directory -Path $workflowDir
Write-FileSafe -Path $workflowPath -Content $workflowContent

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "Created/updated:"
Write-Host "  - $buildScriptPath"
Write-Host "  - $updateScriptPath"
Write-Host "  - $runPipelinePath"
Write-Host "  - $workflowPath"
Write-Host ""
Write-Host "Local full pipeline command:"
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$runPipelinePath`""
Write-Host ""
Write-Host "Then commit & push workflow and scripts to GitHub."
Write-Host "To publish a release, create a tag 'vX.Y.Z' and push it."
