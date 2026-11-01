# open-qwenpaw.ps1 -- ensure the QwenPaw service (port 8088) is running, then open it.
#
# ASCII-only on purpose: this file is launched by Windows PowerShell 5.1, which reads a
# UTF-8 file WITHOUT a BOM as ANSI and would mangle non-ASCII text.
#
# Called hidden by QwenPaw-Launcher.vbs (and by the desktop shortcut that points to it).
#   1) if http://127.0.0.1:8088/api/version already answers -> just open the browser
#   2) otherwise start `qwenpaw app` hidden and wait until it really answers (max 120s)
#   3) always append one line to launchers\qwenpaw-launcher.log
#
# Why this exists:
#   N.E.K.O. (Project N.E.K.O., Steam appid 4099310) connects to a SEPARATELY RUNNING
#   QwenPaw instance.  Its OpenClaw switch probes http://127.0.0.1:8088/api/version and
#   then sends chat turns to http://127.0.0.1:8088/api/console/chat.  If QwenPaw is not
#   up, N.E.K.O.'s Agent panel shows "OpenClaw(QwenPaw) unavailable".
#
#   The pan-* / ST / ComfyUI launchers on this desktop all clear PYTHONPATH / PYTHONHOME /
#   VIRTUAL_ENV before starting a bundled Python: the Hermes venv leaks into child
#   processes and breaks imports.  Same treatment here.
#
# -NoBrowser : do NOT open the browser (used when a caller is already a browser page).

param([switch]$NoBrowser)

$ErrorActionPreference = 'SilentlyContinue'

$url     = 'http://127.0.0.1:8088'
$probe   = "$url/api/version"
$exe     = 'C:\Users\Administrator\.qwenpaw\venv\Scripts\qwenpaw.exe'
$workDir = 'C:\Users\Administrator\.qwenpaw'
$logFile = Join-Path $PSScriptRoot 'qwenpaw-launcher.log'

function Say([string]$m) {
    try {
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
    } catch {}
}

function Test-QwenPawUp {
    try {
        $r = Invoke-WebRequest -Uri $probe -UseBasicParsing -TimeoutSec 6
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $exe)) {
    Say "ERROR: qwenpaw.exe not found at $exe"
    exit 1
}

if (Test-QwenPawUp) {
    Say 'already running on 8088 - opening browser only'
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

Say 'not running - starting qwenpaw app on 127.0.0.1:8088'

# Keep the Hermes venv from polluting the bundled QwenPaw python.
$env:PYTHONPATH  = ''
$env:PYTHONHOME  = ''
$env:VIRTUAL_ENV = ''

Start-Process -FilePath $exe `
    -ArgumentList 'app', '--host', '127.0.0.1', '--port', '8088', '--log-level', 'info' `
    -WorkingDirectory $workDir `
    -WindowStyle Hidden

for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    if (Test-QwenPawUp) {
        Say ("ready after {0}s" -f (($i + 1) * 2))
        if (-not $NoBrowser) { Start-Process $url }
        exit 0
    }
}

Say 'TIMEOUT: 8088 did not answer within 120s - check C:\Users\Administrator\.qwenpaw\qwenpaw.log'
exit 2
