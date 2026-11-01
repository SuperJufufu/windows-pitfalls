[CmdletBinding()]
param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Same interpreter hygiene as the Open WebUI launcher: a leaked PYTHONPATH makes
# the venv import pydantic from another environment and everything fails.
$env:PYTHONPATH = $null
$env:PYTHONHOME = $null
$env:VIRTUAL_ENV = $null
$env:PYTHONSTARTUP = $null
$env:PYTHONUTF8 = '1'

$AppRoot = Join-Path $env:USERPROFILE '.local\Bonsai-Prism\OpenWebUI'
$Python = Join-Path $AppRoot '.venv\Scripts\python.exe'
$Scripts = Join-Path $AppRoot 'demo\scripts\openwebui'
$Logs = Join-Path $AppRoot 'logs'

# port -> script. The Bonsai proxy must be up before SillyTavern talks to it, and
# the ComfyUI bridge before an image is requested.
$Bridges = @(
    @{ Port = 8020; Script = 'st_bonsai_bridge.py'; Name = 'Bonsai 规范化代理' },
    @{ Port = 8189; Script = 'st_comfy_bridge.py';  Name = '显存串行化桥接' }
)

function Test-Port([int]$Port) {
    return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Write-Status([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

Write-Status '正在准备 SillyTavern 生图桥接 ...'

foreach ($b in $Bridges) {
    $path = Join-Path $Scripts $b.Script
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Status ("  [跳过] 找不到 {0}" -f $b.Script)
        continue
    }
    if (Test-Port $b.Port) {
        Write-Status ("  [已在运行] {0} (端口 {1})" -f $b.Name, $b.Port)
        continue
    }
    $stdout = Join-Path $Logs ("{0}-stdout.log" -f [IO.Path]::GetFileNameWithoutExtension($b.Script))
    $stderr = Join-Path $Logs ("{0}-stderr.log" -f [IO.Path]::GetFileNameWithoutExtension($b.Script))
    Start-Process -FilePath $Python -ArgumentList @($path) -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $deadline = (Get-Date).AddSeconds(45)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Port $b.Port) { $ready = $true; break }
        Start-Sleep -Milliseconds 750
    }
    if ($ready) {
        Write-Status ("  [已启动] {0} (端口 {1})" -f $b.Name, $b.Port)
    }
    else {
        Write-Status ("  [失败] {0} 未监听端口 {1},见 {2}" -f $b.Name, $b.Port, $stderr)
    }
}

# ComfyUI itself must be running or the image bridge has nothing to forward to.
$comfy = $false
try {
    $null = Invoke-RestMethod 'http://127.0.0.1:8188/system_stats' -TimeoutSec 5
    $comfy = $true
}
catch { $comfy = $false }
Write-Status ("  ComfyUI (8188): {0}" -f $(if ($comfy) { '在线' } else { '未运行 —— 生图前请先启动 ComfyUI' }))

$bonsai = $false
try {
    $null = Invoke-RestMethod 'http://127.0.0.1:8010/v1/models' -TimeoutSec 5
    $bonsai = $true
}
catch { $bonsai = $false }
Write-Status ("  Bonsai (8010): {0}" -f $(if ($bonsai) { '在线' } else { '未运行 —— 酒馆聊天需要它,生图桥接会自行让位' }))

Write-Status ''
Write-Status '桥接就绪。在 SillyTavern 里每条 AI 回复后会自动生成配图。'
exit 0
