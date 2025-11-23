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
