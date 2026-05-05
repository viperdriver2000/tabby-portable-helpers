# Tabby Start-Wrapper with dynamic Pageant pipe path
#
# Updates Tabby's agentPath via Update-PageantPath.ps1 (so the running
# Pageant instance is correctly registered) and then launches Tabby.
#
# Usage:
#   .\Start-Tabby.ps1            # Update agentPath and start Tabby
#   .\Start-Tabby.ps1 -OnlyUpdate # Update only, do not launch
#                                # (use .\Update-PageantPath.ps1 directly
#                                #  for clearer intent in scripts)

[CmdletBinding()]
param(
    [switch]$OnlyUpdate
)

$ErrorActionPreference = 'Stop'

$TabbyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TabbyExe = Join-Path $TabbyDir 'Tabby.exe'
$UpdateScript = Join-Path $TabbyDir 'Update-PageantPath.ps1'

# --- Update agentPath via dedicated script ---
if (Test-Path $UpdateScript) {
    # Don't fail Start-Tabby if the update step has issues (Pageant not
    # running, config.yaml missing, etc.). The dedicated script prints
    # its own diagnostics.
    try { & $UpdateScript -TabbyDir $TabbyDir } catch { Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Yellow }
}
else {
    Write-Host "[!] Update-PageantPath.ps1 not found - skipping agentPath update" -ForegroundColor Yellow
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
