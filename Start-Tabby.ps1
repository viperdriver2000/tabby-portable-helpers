# Tabby Start-Wrapper with dynamic Pageant pipe path
#
# Pageant generates its named pipe via CryptProtectMemory, which produces
# different hashes after every reboot. Tabby's russh-based agent code
# cannot resolve this pipe automatically on non-domain-joined Windows
# machines, so this script discovers the pipe and patches Tabby's
# config.yaml before launching Tabby.
#
# If the ssh: block / agentType / agentPath are missing, they will be
# created automatically.
#
# Usage:
#   .\Start-Tabby.ps1            # Update agentPath and start Tabby
#   .\Start-Tabby.ps1 -OnlyUpdate # Only update config, do not start

[CmdletBinding()]
param(
    [switch]$OnlyUpdate
)

$ErrorActionPreference = 'Stop'

$TabbyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TabbyExe = Join-Path $TabbyDir 'Tabby.exe'
$ConfigFile = Join-Path $TabbyDir 'data\config.yaml'

# --- Find Pageant named pipe ---
$pipes = Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^pageant\.' }

if (-not $pipes) {
    Write-Host "[!] Pageant is not running - agentPath will not be updated" -ForegroundColor Yellow
}
else {
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
}

if ($OnlyUpdate) {
    return
}

# --- Launch Tabby ---
$running = Get-Process -Name 'Tabby' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[i] Tabby is already running" -ForegroundColor Cyan
}
else {
    if (-not (Test-Path $TabbyExe)) {
        Write-Host "[!] Tabby.exe not found: $TabbyExe" -ForegroundColor Red
        exit 1
    }
    Write-Host "[+] Starting Tabby..." -ForegroundColor Green
    Start-Process -FilePath $TabbyExe
}
