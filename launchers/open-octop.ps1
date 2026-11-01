# open-octop.ps1 -- ensure the Octop server (port 8089) is running, then open it.
#
# ASCII-only on purpose: launched by Windows PowerShell 5.1, which reads a
# UTF-8 file WITHOUT a BOM as ANSI and would mangle non-ASCII text.
# (Learned the hard way: Chinese comments in .ps1 caused a parser error.)
#
#   1) if http://127.0.0.1:8089/ already answers -> just open the browser
#   2) otherwise start `octop run` hidden and wait until it really answers (max 120s)
#   3) always append one line to launchers\octop-launcher.log
#
# Notes:
#   - Port 8089 chosen to avoid 8088 (QwenPaw / OpenClaw backend).
#   - octop.exe lives in %USERPROFILE%\.local\bin, installed via `uv tool install octop`.
#   - Hermes venv leaks into child processes; clear PYTHONPATH/PYTHONHOME/VIRTUAL_ENV.
#   - First run needs `octop init` (creates ~/.octop). This script detects that.

param([switch]$NoBrowser)

$ErrorActionPreference = 'SilentlyContinue'

$port    = 8089
$url     = "http://127.0.0.1:$port"
$exe     = Join-Path $env:USERPROFILE '.local\bin\octop.exe'
$workDir = $env:USERPROFILE
$logFile = Join-Path $PSScriptRoot 'octop-launcher.log'
$dataDir = Join-Path $env:USERPROFILE '.octop'

function Say([string]$m) {
    try {
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
    } catch {}
}

function Test-OctopUp {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 6
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    } catch {
        # A 4xx still means the server is listening. Probe the port directly.
        try {
            $c = New-Object Net.Sockets.TcpClient
            $c.Connect('127.0.0.1', $port)
            $ok = $c.Connected
            $c.Close()
            return $ok
        } catch { return $false }
    }
}

if (-not (Test-Path -LiteralPath $exe)) {
    Say "ERROR: octop.exe not found at $exe"
    Write-Host "octop.exe not found. Reinstall with: uv tool install octop" -ForegroundColor Red
    exit 1
}

if (Test-OctopUp) {
    Say "already running on $port - opening browser only"
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

# not initialized yet?
if (-not (Test-Path -LiteralPath $dataDir)) {
    Say "NOT INITIALIZED: $dataDir missing - run 'octop init' first"
    Write-Host ""
    Write-Host "Octop is installed but NOT initialized yet." -ForegroundColor Yellow
    Write-Host "Run this once in a terminal:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '  octop init --admin-username admin --admin-password <your-password>' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Then double-click this shortcut again." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 8
    exit 3
}

Say "not running - starting octop on 127.0.0.1:$port"

# Keep the Hermes venv from polluting the octop python.
$env:PYTHONPATH  = ''
$env:PYTHONHOME  = ''
$env:VIRTUAL_ENV = ''

# CRITICAL: bypass the Windows system proxy for local endpoints.
# httpx (used by Octop's provider probe / langchain) honours HTTP_PROXY /
# NO_PROXY env vars but does NOT read Windows' ProxyOverride registry list.
# With Clash Verge running (127.0.0.1:7892), every request - including
# 127.0.0.1:8010 (Bonsai) and 127.0.0.1:11434 (Ollama) - would be sent to the
# proxy and fail with "model service unavailable", even though curl works.
# Verified 2026-10-18: probe went from failed to ok/latency=1232ms once these
# were set.
$env:NO_PROXY  = '127.0.0.1,localhost,::1'
$env:no_proxy  = '127.0.0.1,localhost,::1'

Start-Process -FilePath $exe `
    -ArgumentList 'run', '--host', '127.0.0.1', '--port', "$port" `
    -WorkingDirectory $workDir `
    -WindowStyle Hidden

for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    if (Test-OctopUp) {
        Say ("ready after {0}s" -f (($i + 1) * 2))
        if (-not $NoBrowser) { Start-Process $url }
        exit 0
    }
}

Say "TIMEOUT: $port did not answer within 120s - check ~/.octop logs"
Write-Host "Octop did not come up within 120s. Check ~/.octop for logs." -ForegroundColor Red
exit 2
