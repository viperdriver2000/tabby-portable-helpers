# Tabby Portable Update Script
#
# Checks GitHub Releases for newer Tabby versions, downloads the
# Portable build and installs it while preserving the data/ directory
# (config.yaml, profiles, plugins, etc.).
#
# Usage:
#   .\Update-Tabby.ps1                  # Update to latest version
#   .\Update-Tabby.ps1 -Check           # Only check, do not install
#   .\Update-Tabby.ps1 -Force           # Re-install even if already up to date
#   .\Update-Tabby.ps1 -ListVersions    # Show available versions on GitHub
#   .\Update-Tabby.ps1 -Version 1.0.230 # Install a specific version (downgrade
#                                       # or pin to a known-good release)

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force,
    [switch]$ListVersions,
    [string]$Version
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

function Get-AssetForVersion {
    param([Parameter(Mandatory)][PSCustomObject]$Release)
    $version = $Release.tag_name -replace '^v', ''
    $asset = $Release.assets | Where-Object { $_.name -eq "tabby-$version-portable-x64.zip" }
    if (-not $asset) {
        throw "Asset 'tabby-$version-portable-x64.zip' not found in release."
    }
    return [PSCustomObject]@{
        Version = $version
        Url     = $asset.browser_download_url
        Size    = $asset.size
    }
}

function Get-LatestVersion {
    $api = 'https://api.github.com/repos/Eugeny/tabby/releases/latest'
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Tabby-Updater' }
    return Get-AssetForVersion -Release $release
}

function Get-VersionList {
    param([int]$PerPage = 30)
    $api = "https://api.github.com/repos/Eugeny/tabby/releases?per_page=$PerPage"
    $releases = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Tabby-Updater' }
    return $releases | ForEach-Object {
        $ver = $_.tag_name -replace '^v', ''
        $hasAsset = ($_.assets | Where-Object { $_.name -eq "tabby-$ver-portable-x64.zip" }) -ne $null
        [PSCustomObject]@{
            Version    = $ver
            Published  = ([DateTime]$_.published_at).ToString('yyyy-MM-dd')
            Prerelease = $_.prerelease
            HasPortable = $hasAsset
        }
    }
}

function Get-SpecificVersion {
    param([string]$Tag)
    # GitHub accepts both "v1.0.230" and "1.0.230" — normalise to "v..."
    if (-not $Tag.StartsWith('v')) { $Tag = "v$Tag" }
    $api = "https://api.github.com/repos/Eugeny/tabby/releases/tags/$Tag"
    try {
        $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Tabby-Updater' }
    }
    catch {
        throw "Release '$Tag' not found on GitHub. Run with -ListVersions to see available versions."
    }
    return Get-AssetForVersion -Release $release
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

# --- ListVersions: show available releases and exit ---
if ($ListVersions) {
    Write-Step "Available Tabby versions on GitHub" 'Magenta'
    Write-Host ""
    $current = Get-CurrentVersion
    $versions = Get-VersionList
    Write-Host ("  {0,-12} {1,-12} {2,-10} {3}" -f 'Version', 'Published', 'Prerelease', 'Notes')
    Write-Host ("  {0,-12} {1,-12} {2,-10} {3}" -f '-------', '---------', '----------', '-----')
    foreach ($v in $versions) {
        $marker = ''
        if ($v.Version -eq $current) { $marker = '<-- current' }
        $color = if ($v.Prerelease) { 'DarkGray' } elseif (-not $v.HasPortable) { 'DarkGray' } else { 'Gray' }
        $note = if (-not $v.HasPortable) { '(no x64 portable asset)' } else { $marker }
        Write-Host ("  {0,-12} {1,-12} {2,-10} {3}" -f $v.Version, $v.Published, $v.Prerelease, $note) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "Install a specific version with:" -ForegroundColor Cyan
    Write-Host "  .\Update-Tabby.ps1 -Version <version>" -ForegroundColor Cyan
    return
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

# --- Resolve target version: explicit -Version takes precedence over latest ---
if ($Version) {
    Write-Step "Fetching version $Version from GitHub..."
    $latest = Get-SpecificVersion -Tag $Version
    Write-Host "  Target version:  $($latest.Version)"
}
else {
    Write-Step "Fetching latest version from GitHub..."
    $latest = Get-LatestVersion
    Write-Host "  Latest version:  $($latest.Version)"
}
Write-Host "  Download size:   $([math]::Round($latest.Size / 1MB, 1)) MB"
Write-Host ""

if ($current -eq $latest.Version -and -not $Force) {
    Write-Host "Tabby is already at version $($latest.Version)." -ForegroundColor Green
    Write-Host "Use -Force to re-install." -ForegroundColor DarkGray
    return
}

if ($Check) {
    if ($current -ne $latest.Version) {
        Write-Host "Update available: $current -> $($latest.Version)" -ForegroundColor Yellow
    }
    return
}

# Detect downgrade and call it out clearly
$action = 'update'
if ($current -and $latest.Version -and ([System.Version]$current -gt [System.Version]$latest.Version)) {
    $action = 'DOWNGRADE'
    Write-Host "WARNING: This will DOWNGRADE Tabby from $current to $($latest.Version)." -ForegroundColor Yellow
}

if (-not $Force) {
    Write-Host ("Proceed with {0}? [Y/n]: " -f $action) -ForegroundColor Yellow -NoNewline
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
    New-Item -ItemType Directory -Path $extractDir | Out-Null

    # The Tabby ZIP contains paths > 260 chars (internal node-gyp
    # build artefacts). PowerShell's Expand-Archive and .NET's
    # ZipFile.ExtractToDirectory both choke on these on systems
    # without long-path support enabled.
    #
    # Windows 10+ ships a real tar.exe (BSD libarchive) that handles
    # long paths transparently. Use it if available, fall back to
    # .NET otherwise.
    $tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tarExe) {
        & tar.exe -x -f $zipFile -C $extractDir
        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe failed to extract archive (exit code $LASTEXITCODE)."
        }
    }
    else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractDir)
    }

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

    Write-Step "Installing new version..."
    # Use robocopy: it handles long paths (>260 chars) transparently
    # and is much faster than Copy-Item -Recurse for large trees.
    # /XD "data" excludes the data directory if the archive contains
    # one (it shouldn't, but defense in depth). Existing data/ in the
    # target is left untouched.
    # Robocopy exit codes: 0-7 = success (1=files copied, 0=nothing to do)
    & robocopy.exe $extractedRoot $TabbyDir /E /XD (Join-Path $extractedRoot 'data') /NFL /NDL /NJH /NJS /NC /NS /NP /R:2 /W:1 > $null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }

    $newVersion = Get-CurrentVersion
    if ($newVersion -eq $latest.Version) {
        Write-Host ""
        Write-Host "$($action -replace 'DOWNGRADE','Downgrade' -replace 'update','Update') successful: $current -> $newVersion" -ForegroundColor Green
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
