# Update Tabby's agentPath to the current Pageant pipe
#
# Pageant generates its named pipe via CryptProtectMemory, which produces
# different hashes after every reboot/logout. This script discovers the
# active Pageant pipe and rewrites the `agentPath` entry in Tabby's
# config.yaml accordingly.
#
# If the ssh: block / agentType / agentPath are missing, they will be
# created automatically.
#
# Usage:
#   .\Update-PageantPath.ps1                 # auto-detect Tabby dir from script location
#   .\Update-PageantPath.ps1 -TabbyDir 'C:\Path\To\Tabby'
#
# Designed to be safe to run repeatedly (idempotent) and from external
# launchers (e.g. an AutoIt script that also starts Pageant).

[CmdletBinding()]
param(
    [string]$TabbyDir
)

$ErrorActionPreference = 'Stop'

if (-not $TabbyDir) {
    $TabbyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$ConfigFile = Join-Path $TabbyDir 'data\config.yaml'

# --- Find Pageant named pipe ---
$pipes = Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^pageant\.' }

if (-not $pipes) {
    Write-Host "[!] Pageant is not running - agentPath not updated" -ForegroundColor Yellow
    exit 2
}

if ($pipes -is [array]) {
    $pipeName = $pipes[0].Name
}
else {
    $pipeName = $pipes.Name
}
$pipe = "\\.\pipe\$pipeName"
Write-Host "[+] Pageant pipe: $pipe" -ForegroundColor Green

if (-not (Test-Path $ConfigFile)) {
    Write-Host "[!] config.yaml not found: $ConfigFile" -ForegroundColor Red
    Write-Host "    Run Tabby once to generate it, then re-run this script." -ForegroundColor Yellow
    exit 1
}

$content = Get-Content $ConfigFile -Raw
$newAgentPathLine = "  agentPath: '$pipe'"
$agentPathPattern = "(?ms)^  agentPath:.*?(?=\r?\n  [a-zA-Z]|\r?\n[a-zA-Z])"

if ($content -match $agentPathPattern) {
    $oldMatch = $matches[0]
    $oldHash = '(unknown)'
    if ($oldMatch -match 'pageant\.[^.]+\.([0-9a-f]+)') {
        $oldHash = $matches[1]
    }

    $newHash = '(unknown)'
    if ($pipeName -match 'pageant\.[^.]+\.([0-9a-f]+)') {
        $newHash = $matches[1]
    }

    if ($oldHash -eq $newHash) {
        Write-Host "[=] agentPath already up to date" -ForegroundColor Cyan
    }
    else {
        $newContent = $content -replace $agentPathPattern, $newAgentPathLine
        Set-Content -Path $ConfigFile -Value $newContent -NoNewline
        Write-Host "[+] agentPath updated: $oldHash -> $newHash" -ForegroundColor Green
    }
}
elseif ($content -match '(?m)^  agentType:\s*named-pipe\s*$') {
    $newContent = $content -replace '(?m)(^  agentType:\s*named-pipe\s*)$', "`$1`n$newAgentPathLine"
    Set-Content -Path $ConfigFile -Value $newContent -NoNewline
    Write-Host "[+] agentPath inserted" -ForegroundColor Green
}
elseif ($content -match '(?m)^ssh:\s*$') {
    $injection = "  agentType: named-pipe`n$newAgentPathLine"
    $newContent = $content -replace '(?m)(^ssh:\s*)$', "`$1`n$injection"
    Set-Content -Path $ConfigFile -Value $newContent -NoNewline
    Write-Host "[+] agentType + agentPath added to ssh: block" -ForegroundColor Green
}
else {
    $injection = "`nssh:`n  agentType: named-pipe`n$newAgentPathLine`n"
    Add-Content -Path $ConfigFile -Value $injection
    Write-Host "[+] ssh: block created with agentType + agentPath" -ForegroundColor Green
}
