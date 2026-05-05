# Tabby Portable Update Script
#
# Checks GitHub Releases for newer Tabby versions, downloads the
# Portable build and installs it while preserving the data/ directory
# (config.yaml, profiles, plugins, etc.).
#
# Usage:
#   .\Update-Tabby.ps1           # Update to latest version
#   .\Update-Tabby.ps1 -Check    # Only check, do not install
#   .\Update-Tabby.ps1 -Force    # Re-install even if already up to date

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$TabbyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TabbyExe = Join-Path $TabbyDir 'Tabby.exe'
$DataDir = Join-Path $TabbyDir 'data'

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host ">> $Msg" -ForegroundColor $Color
}

function Get-CurrentVersion {
    if (-not (Test-Path $TabbyExe)) {
        return $null
    }
    $info = (Get-Item $TabbyExe).VersionInfo
    return $info.ProductVersion -replace '\.0$', ''
}

function Get-LatestVersion {
    $api = 'https://api.github.com/repos/Eugeny/tabby/releases/latest'
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Tabby-Updater' }
    $version = $release.tag_name -replace '^v', ''
    $asset = $release.assets | Where-Object { $_.name -eq "tabby-$version-portable-x64.zip" }
    if (-not $asset) {
        throw "Asset 'tabby-$version-portable-x64.zip' not found in release."
    }
    return [PSCustomObject]@{
        Version = $version
        Url     = $asset.browser_download_url
        Size    = $asset.size
    }
}

function Stop-Tabby {
    $procs = Get-Process -Name 'Tabby' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Step "Stopping running Tabby processes ($($procs.Count) processes)..."
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 2
        $still = Get-Process -Name 'Tabby' -ErrorAction SilentlyContinue
        if ($still) {
            throw "Could not stop all Tabby processes. Please close them manually."
        }
    }
}

Write-Step "Tabby Update Check" 'Magenta'
Write-Host ""

$current = Get-CurrentVersion
if ($current) {
    Write-Host "  Current version: $current"
}
else {
    Write-Host "  Current version: (no installation found)"
}

Write-Step "Fetching latest version from GitHub..."
$latest = Get-LatestVersion
Write-Host "  Latest version:  $($latest.Version)"
Write-Host "  Download size:   $([math]::Round($latest.Size / 1MB, 1)) MB"
Write-Host ""

if ($current -eq $latest.Version -and -not $Force) {
    Write-Host "Tabby is already up to date." -ForegroundColor Green
    return
}

if ($Check) {
    if ($current -ne $latest.Version) {
        Write-Host "Update available: $current -> $($latest.Version)" -ForegroundColor Yellow
    }
    return
}

if (-not $Force) {
    Write-Host "Proceed with update? [Y/n]: " -ForegroundColor Yellow -NoNewline
    $answer = Read-Host
    if ($answer -and $answer -notmatch '^[jJyY]') {
        Write-Host "Aborted." -ForegroundColor Red
        return
    }
}

$tempDir = Join-Path $env:TEMP "tabby-update-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$zipFile = Join-Path $tempDir "tabby-$($latest.Version).zip"

try {
    Write-Step "Downloading to $zipFile..."
    $progressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $latest.Url -OutFile $zipFile -UseBasicParsing
    $progressPreference = 'Continue'

    Write-Step "Extracting archive..."
    $extractDir = Join-Path $tempDir 'extracted'
    # Use .NET ZipFile API instead of Expand-Archive: it's faster and
    # avoids spurious cleanup-related "PathNotFound" errors that can
    # happen with Expand-Archive on large archives.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractDir)

    $extractedRoot = $extractDir
    $extractedExe = Join-Path $extractedRoot 'Tabby.exe'
    if (-not (Test-Path $extractedExe)) {
        $sub = Get-ChildItem $extractDir -Directory | Select-Object -First 1
        if ($sub) {
            $extractedRoot = $sub.FullName
            $extractedExe = Join-Path $extractedRoot 'Tabby.exe'
        }
    }
    if (-not (Test-Path $extractedExe)) {
        throw "Tabby.exe not found in extracted archive."
    }

    Stop-Tabby

    Write-Step "Backing up data/ directory..."
    $dataBackup = Join-Path $tempDir 'data-backup'
    if (Test-Path $DataDir) {
        Copy-Item -Path $DataDir -Destination $dataBackup -Recurse
    }

    Write-Step "Installing new version..."
    $items = Get-ChildItem $extractedRoot
    foreach ($item in $items) {
        if ($item.Name -eq 'data') {
            continue
        }
        $dest = Join-Path $TabbyDir $item.Name
        if (Test-Path $dest) {
            Remove-Item -Path $dest -Recurse -Force
        }
        Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force
    }

    if ((Test-Path $dataBackup) -and -not (Test-Path $DataDir)) {
        Write-Step "Restoring data/ directory..."
        Copy-Item -Path $dataBackup -Destination $DataDir -Recurse
    }

    $newVersion = Get-CurrentVersion
    if ($newVersion -eq $latest.Version) {
        Write-Host ""
        Write-Host "Update successful: $current -> $newVersion" -ForegroundColor Green
    }
    else {
        Write-Host "Warning: version verification failed. Expected: $($latest.Version), got: $newVersion" -ForegroundColor Yellow
    }
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
