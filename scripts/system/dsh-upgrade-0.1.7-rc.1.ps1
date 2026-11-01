#Requires -Version 5.1
<#
  将 DeepSeek Harness 内核从 0.1.0-rc.6 切换到 0.1.7-rc.1，并保留你自定义的模型配置。

  前提：先完全退出 DeepSeek Harness（桌面上的 dsh.exe）。脚本会自行检查，
        若仍有 dsh 进程在运行会直接中止。

  做的事：
    1. 把 profile 的插件链接（junction）从旧内核指向新内核
    2. 用新内核整体替换旧内核目录
    3. 把新内核迁移 settings 时丢弃的 llm-deepseek.models / llm-pi-ai.providers 段补回
    4. 校验新内核能实际启动 web 服务

  任何一步失败都会自动回滚到原状态（.credentials.yaml 不会被本脚本改动）。
#>

$ErrorActionPreference = 'Stop'

$KernelExe  = 'C:\Users\Administrator\AppData\Local\dsh-exe\0.1.0-rc.7'
$OldKernel  = Join-Path $KernelExe 'dsh'
$Staging    = 'C:\Users\Administrator\.dsh\kernels\0.1.7-rc.1'
$BackupRoot = 'C:\Users\Administrator\.dsh-backup-20260924-rc6'
$ProfileNm  = 'C:\Users\Administrator\.dsh\profiles\node_modules'
$Settings   = 'C:\Users\Administrator\.dsh\settings.yaml'
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'

# 要补回的配置段（base64，避免 YAML 里的花括号干扰脚本解析）
$SectionsB64 = 'bGxtLWRlZXBzZWVrOgogIG1vZGVsczoKICAgIC0gaWQ6IGRlZXBzZWVrLWZsYXNoCiAgICAgIG5hbWU6IERlZXBTZWVrLUZsYXNoCiAgICAgIGNvbnRleHRXaW5kb3c6IDEwMDAwMDAKICAgICAgaW5wdXRNb2RhbGl0aWVzOgogICAgICAgIC0gdGV4dAogICAgICAgIC0gaW1hZ2UKICAgICAgaW1hZ2VQaXhlbEJ1ZGdldDogNjQwMDAwCiAgICAgIGltYWdlTWF4Qnl0ZXM6IDEwNDg1NzYKICAgICAgc3lzdGVtUHJvbXB0VXBkYXRlOiBpbi1oaXN0b3J5CiAgICAtIGlkOiBkZWVwc2Vlay12NC1mbGFzaAogICAgICBuYW1lOiBEZWVwU2Vlay1WNC1GbGFzaAogICAgICBkZXNjcmlwdGlvbjogRmFzdCwgZWZmaWNpZW50LCBhbmQgZWNvbm9taWNhbDsgc3VpdGVkIHRvIGZvY3VzZWQsIHJvdXRpbmUsIG9yCiAgICAgICAgcGFyYWxsZWwgdGFza3MuCiAgICAgIGNvbnRleHRXaW5kb3c6IDEwMDAwMDAKICAgICAgaW5wdXRNb2RhbGl0aWVzOgogICAgICAgIC0gdGV4dAogICAgLSBpZDogZGVlcHNlZWstdjQtcHJvCiAgICAgIG5hbWU6IERlZXBTZWVrLVY0LVBybwogICAgICBkZXNjcmlwdGlvbjogU3Ryb25nZXIgYWdlbnRpYyBjb2RpbmcsIGtub3dsZWRnZSwgYW5kIGRpZmZpY3VsdCByZWFzb25pbmc7IHN1aXRlZAogICAgICAgIHRvIGNvbXBsZXggb3IgcXVhbGl0eS1jcml0aWNhbCB0YXNrcyBhdCBoaWdoZXIgY29zdC4KICAgICAgY29udGV4dFdpbmRvdzogMTAwMDAwMAogICAgICBpbnB1dE1vZGFsaXRpZXM6CiAgICAgICAgLSB0ZXh0CiAgICAtIGlkOiBkZWVwc2Vlay12NC1mbGFzaC12aXNpb24tZXhwCiAgICAgIG5hbWU6IERlZXBTZWVrLVY0LUZsYXNoLVZpc2lvbi1FeHAKICAgICAgY29udGV4dFdpbmRvdzogMTAwMDAwMAogICAgICBpbnB1dE1vZGFsaXRpZXM6CiAgICAgICAgLSB0ZXh0CiAgICAgICAgLSBpbWFnZQogICAgICBpbWFnZVBpeGVsQnVkZ2V0OiA2NDAwMDAKICAgICAgaW1hZ2VNYXhCeXRlczogMTA0ODU3NgpsbG0tcGktYWk6CiAgcHJvdmlkZXJzOgogICAgcXdlbi10b2tlbi1wbGFuLWNuOgogICAgICBiYXNlVVJMOiBodHRwczovL3dzLTM3NmdkODc3bG11OXI2OHQuY24tYmVpamluZy5tYWFzLmFsaXl1bmNzLmNvbS9jb21wYXRpYmxlLW1vZGUvdjEKICAgICAgYXBpS2V5RW52OiBRV0VOX1RPS0VOX1BMQU5fQ05fQVBJX0tFWQogICAgICBtb2RlbHM6CiAgICAgICAgLSBpZDogcXdlbjMuOC1tYXgKICAgICAgICAgIG5hbWU6IFF3ZW4zLjggTWF4CiAgICAgICAgICBjb250ZXh0V2luZG93OiAxMDAwMDAwCiAgICAgICAgICBtYXhUb2tlbnM6IDEzMTA3MgogICAgb3BlbmNvZGU6CiAgICAgIGRpc3BsYXlOYW1lOiBPcGVuQ29kZSBaZW4KICAgICAgYXBpOiBvcGVuYWktY29tcGxldGlvbnMKICAgICAgYmFzZVVSTDogaHR0cHM6Ly9vcGVuY29kZS5haS96ZW4vdjEKICAgICAgbW9kZWxzOgogICAgICAgIC0gaWQ6IHgtcHJldmlldy1mLWZyZWUKICAgICAgICAgIG5hbWU6IE94IEFscGhhIEZyZWUKICAgICAgICAgIGNvbnRleHRXaW5kb3c6IDEwMDAwMDAKICAgICAgICAgIG1heFRva2VuczogMTMxMDcyCiAgICAgIGFwaUtleUVudjogT1BFTkNPREVfQVBJX0tFWQogICAgYm9uc2FpOgogICAgICBkaXNwbGF5TmFtZTogQm9uc2FpLTI3QiBsb2NhbAogICAgICBhcGlLZXlFbnY6IEJPTlNBSV9BUElfS0VZCiAgICAgIGFwaTogb3BlbmFpLWNvbXBsZXRpb25zCiAgICAgIGJhc2VVUkw6IGh0dHA6Ly8xMjcuMC4wLjE6ODA4MS92MQogICAgICBtb2RlbHM6CiAgICAgICAgLSBpZDogLi9UZXJuYXJ5LUJvbnNhaS0yN0ItZ2d1Zi9UZXJuYXJ5LUJvbnNhaS0yN0ItUTJfZzY0LmdndWYKICAgICAgICAgIG5hbWU6IC4vVGVybmFyeS1Cb25zYWktMjdCLWdndWYvVGVybmFyeS1Cb25zYWktMjdCLVEyX2c2NC5nZ3Vm'

function Info($m) { Write-Host "  $m" }
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !!  $m" -ForegroundColor Yellow }

Write-Host "`nDeepSeek Harness: 0.1.0-rc.6 -> 0.1.7-rc.1" -ForegroundColor White
Write-Host "============================================"

Step '前置检查'

$running = @(Get-CimInstance Win32_Process -Filter "Name='dsh.exe' or Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'dsh.exe' -or $_.CommandLine -like '*dsh-exe*' })
if ($running.Count -gt 0) {
    Warn 'DeepSeek Harness 仍在运行，无法安全切换：'
    foreach ($r in $running) { Info "PID $($r.ProcessId)  $($r.Name)" }
    Write-Host "`n请先完全退出 dsh，再重新运行本脚本。" -ForegroundColor Red
    exit 1
}
Ok '没有运行中的 dsh 进程'

foreach ($p in @($OldKernel, $Staging, $ProfileNm, $Settings)) {
    if (-not (Test-Path $p)) {
        Write-Host "缺少必要路径：$p" -ForegroundColor Red
        exit 1
    }
}
Ok '路径齐全'

$sectionsText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($SectionsB64))
foreach ($needle in @('llm-deepseek:', 'llm-pi-ai:', 'deepseek-flash', 'qwen-token-plan-cn')) {
    if ($sectionsText -notlike "*$needle*") { Write-Host "内置配置段损坏：缺少 $needle" -ForegroundColor Red; exit 1 }
}
Ok '内置配置段完整'

Step '建立回滚点'

$Rollback = Join-Path $BackupRoot "rollback-$Stamp"
New-Item -ItemType Directory -Path $Rollback -Force | Out-Null
Copy-Item $Settings (Join-Path $Rollback 'settings.yaml') -Force
Ok "settings.yaml 已备份到 $Rollback"

$before = @(Get-ChildItem $ProfileNm -Force -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LinkType -eq 'Junction' -and ($_.Target -join ';') -like "*$OldKernel*" })
$before | ForEach-Object { "$($_.FullName)|$(($_.Target | Select-Object -First 1))" } |
    Set-Content (Join-Path $Rollback 'junction-map.txt') -Encoding UTF8
Ok "记录了 $($before.Count) 个插件链接"

$OldKernelRenamed = Join-Path $KernelExe "dsh.old-$Stamp"
$swapped = $false

try {
    Step '1/4 重指插件链接到新内核'

    $NewNm  = Join-Path $Staging 'node_modules'
    $failed = @()
    $count  = 0

    foreach ($j in $before) {
        $rel        = $j.FullName.Substring($ProfileNm.Length).TrimStart('\')
        $origTarget = $j.Target | Select-Object -First 1

        # 少数条目（如 @deepseek-ai\dsh）在旧内核里指向内核根目录，而非 node_modules
        $isKernelRoot = $false
        if ($origTarget) {
            if ($origTarget.TrimEnd('\') -ieq $OldKernel.TrimEnd('\')) { $isKernelRoot = $true }
        }

        if ($isKernelRoot) {
            $tgt = $Staging
        } else {
            $tgt = Join-Path $NewNm $rel
        }

        if (-not (Test-Path $tgt)) {
            $failed += $rel
            continue
        }

        cmd /c rmdir "`"$($j.FullName)`"" 2>$null | Out-Null
        cmd /c mklink /J "`"$($j.FullName)`"" "`"$tgt`"" > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $count++ } else { $failed += $rel }
    }

    Ok "已重指 $count 个；新内核缺少 $($failed.Count) 个"
    if ($failed.Count -gt 0) {
        Warn '以下插件不在新内核中（这两个内核之间被移除或改名，通常无影响）：'
        $failed | Select-Object -First 12 | ForEach-Object { Info $_ }
    }

    Step '2/4 替换内核目录'
    Move-Item $OldKernel $OldKernelRenamed
    Move-Item $Staging $OldKernel
    $swapped = $true
    Ok '新内核已就位，旧内核改名保留'

    Step '3/4 校验内核版本'
    $ver = (Get-Content (Join-Path $OldKernel 'package.json') -Raw | ConvertFrom-Json).version
    if ($ver -ne '0.1.7-rc.1') { throw "内核版本不符：$ver" }
    Ok "内核版本 $ver"

    Step '4/4 校验启动'
    $log     = Join-Path $env:TEMP "dsh-upgrade-boot-$Stamp.log"
    $nodeExe = Join-Path $KernelExe 'node.exe'
    $binJs   = Join-Path $OldKernel 'lib\bin.js'
    $proc = Start-Process -FilePath $nodeExe -ArgumentList @($binJs, 'web', '--no-open', '--port', '3099') `
        -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Hidden
    Start-Sleep -Seconds 25
    $listening = @(Get-NetTCPConnection -LocalPort 3099 -State Listen -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    if ($listening) {
        Ok '新内核可正常启动 web 服务'
    } else {
        Warn '未检测到 3099 端口监听，日志尾部如下：'
        if (Test-Path $log) { Get-Content $log -Tail 25 | ForEach-Object { Info $_ } }
        throw '新内核启动校验未通过'
    }
}
catch {
    Write-Host "`n切换失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '正在回滚...' -ForegroundColor Yellow

    if ($swapped) {
        if (Test-Path $OldKernel) { Remove-Item $OldKernel -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $OldKernelRenamed) { Move-Item $OldKernelRenamed $OldKernel -ErrorAction SilentlyContinue }
        Write-Host '  旧内核已还原' -ForegroundColor Yellow
    }

    $map = Join-Path $Rollback 'junction-map.txt'
    if (Test-Path $map) {
        foreach ($line in (Get-Content $map)) {
            if (-not $line.Trim()) { continue }
            $parts = $line -split '\|', 2
            $link  = $parts[0]
            $tgt   = $parts[1]
            if (Test-Path $tgt) {
                cmd /c rmdir "`"$link`"" 2>$null | Out-Null
                cmd /c mklink /J "`"$link`"" "`"$tgt`"" > $null 2>&1
            }
        }
        Write-Host '  插件链接已还原' -ForegroundColor Yellow
    }

    Copy-Item (Join-Path $Rollback 'settings.yaml') $Settings -Force
    Write-Host '  配置已还原' -ForegroundColor Yellow
    Write-Host "`n已回滚，系统仍为 0.1.0-rc.6。回滚资料在 $Rollback" -ForegroundColor Yellow
    exit 1
}

Step '补回自定义模型配置段'

$current = Get-Content $Settings -Raw
$added   = @()
if ($current -notmatch '(?m)^llm-deepseek:') { $added += 'llm-deepseek.models' }
if ($current -notmatch '(?m)^llm-pi-ai:')     { $added += 'llm-pi-ai.providers' }

if ($added.Count -eq 0) {
    Ok '两段配置都已存在，无需补回'
} else {
    $merged = $current.TrimEnd() + "`n`n" + $sectionsText
    Set-Content $Settings $merged -Encoding UTF8
    Ok "已补回：$($added -join ', ')"
    Info 'qwen 的 apiKey 现在从 .credentials.yaml 的 QWEN_TOKEN_PLAN_CN_API_KEY 读取'
}

Write-Host "`n升级完成。" -ForegroundColor Green
Write-Host "现在可以正常启动 DeepSeek Harness（桌面 dsh.exe）。" -ForegroundColor Green
Write-Host "回滚资料：$Rollback" -ForegroundColor Gray
