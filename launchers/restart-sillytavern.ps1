[CmdletBinding()]
param(
    [int]$Port = 8000,
    [int]$PortFreeTimeoutSec = 40,
    [int]$ReadyTimeoutSec = 90,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Restart SillyTavern without the two traps this script exists to avoid:
#
#   1. Stopping the old process and immediately starting a new one loses the
#      race for the port:  "Error: listen EADDRINUSE: address already in use"
#      and the NEW instance dies while the OLD one keeps serving.
#   2. Probing readiness with "does http://127.0.0.1:8000/ return 200?" reports
#      success even when the new instance never started, because the OLD one
#      answers. Readiness is therefore checked against the NEW process id.
#
# Same interpreter hygiene as the other launchers.
# ---------------------------------------------------------------------------
$env:PYTHONPATH = $null
$env:PYTHONHOME = $null
$env:VIRTUAL_ENV = $null

$StRoot = 'C:\Users\Administrator\SillyTavern-Launcher\SillyTavern'
$Logs = Join-Path $env:USERPROFILE '.local\Bonsai-Prism\OpenWebUI\logs'
$Node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $Node) { $Node = 'C:\Program Files\nodejs\node.exe' }

function Get-SillyTavernProcesses {
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'server\.js' } |
        Select-Object ProcessId, CreationDate, CommandLine
}

function Get-PortOwner([int]$P) {
    $c = Get-NetTCPConnection -State Listen -LocalPort $P -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($c) { return $c.OwningProcess }
    return $null
}

# ---- 0. stand down if someone else looks mid-restart ----------------------
#
# Another DSH session also drives this SillyTavern, and nothing locks the
# instance. On 2026-09-26 at 15:29 two `node server.js` processes were observed
# starting together (parent cmd.exe / Start.bat - not us) and neither was
# listening yet. If more than one instance exists, that is the signature of
# someone else's restart in flight, so defer instead of killing their process.
# Set-StrictMode makes .Count unavailable when the pipeline yields a SINGLE
# object, and one instance is the normal case. @() forces an array so .Count is
# always valid - without it this guard threw
# "The property 'Count' cannot be found on this object".
$existing = @(Get-SillyTavernProcesses)
if ($existing.Count -gt 1 -and -not $Force) {
    Write-Host ("检测到 {0} 个 server.js 实例,像是另一个会话正在重启:" -f $existing.Count)
    foreach ($p in $existing) {
        Write-Host ("    pid={0}  启动于 {1}" -f $p.ProcessId, $p.CreationDate)
    }
    Write-Host '为避免互相抢端口,本次不动作。确认要强制重启请加 -Force。'
    exit 2
}

# ---- 1. stop every server.js instance -------------------------------------
if ($existing) {
    foreach ($p in $existing) {
        Write-Host ("停止旧实例 pid={0}" -f $p.ProcessId)
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host '没有找到运行中的 server.js 实例'
}

# ---- 2. wait for the port to actually be released -------------------------
$deadline = (Get-Date).AddSeconds($PortFreeTimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (-not (Get-PortOwner $Port)) { break }
    Start-Sleep -Milliseconds 400
}
$owner = Get-PortOwner $Port
if ($owner) {
    Write-Host ("错误: 端口 {0} 仍被 pid={1} 占用,放弃启动(避免 EADDRINUSE)" -f $Port, $owner)
    exit 1
}
Write-Host ("端口 {0} 已释放,开始启动" -f $Port)

# ---- 3. start, remembering the new pid ------------------------------------
$stdout = Join-Path $Logs 'sillytavern-stdout.log'
$stderr = Join-Path $Logs 'sillytavern-stderr.log'
$proc = Start-Process -FilePath $Node -ArgumentList @('server.js') -WorkingDirectory $StRoot `
    -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Host ("新实例已拉起 pid={0}" -f $proc.Id)

# ---- 4. ready = the new pid owns the port AND it actually serves ----------
#
# Owning the port is not enough: SillyTavern binds 8000 early in startup and
# keeps loading extensions afterwards, so an HTTP request can still fail at that
# point. Observed exactly that - the script announced readiness and the very next
# request came back DOWN. Both conditions are therefore required.
$deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
$ownsPort = $false
$serves = $false
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) {
        Write-Host ("错误: 新实例 pid={0} 已退出。stderr 末尾:" -f $proc.Id)
        Get-Content $stderr -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { "    $_" }
        exit 1
    }
    $newOwner = Get-PortOwner $Port
    $ownsPort = ($newOwner -eq $proc.Id)
    if ($ownsPort) {
        try {
            $resp = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/" -f $Port) -TimeoutSec 5 -UseBasicParsing
            $serves = ($resp.StatusCode -eq 200)
        }
        catch {
            $serves = $false
        }
    }
    if ($ownsPort -and $serves) {
        Write-Host ("SillyTavern 就绪: 端口 {0} 由新实例 pid={1} 提供服务并返回 200" -f $Port, $proc.Id)
        exit 0
    }
    Start-Sleep -Milliseconds 500
}

if ($ownsPort -and -not $serves) {
    Write-Host ("错误: 新实例 pid={0} 已占用端口 {1},但 {2} 秒内没有返回 HTTP 200" -f $proc.Id, $Port, $ReadyTimeoutSec)
}
else {
    Write-Host ("错误: 等待 {0} 秒后端口 {1} 仍未由新实例 pid={2} 接管" -f $ReadyTimeoutSec, $Port, $proc.Id)
    Write-Host ("当前占用者: {0}" -f ($(if ($newOwner) { $newOwner } else { '无' })))
}
Get-Content $stderr -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { "    $_" }
exit 1
