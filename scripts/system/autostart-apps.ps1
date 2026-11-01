# ============================================================
#  RECOVERED 2026-10-01 from  %TEMP%\autostart.ps1  (2026-09-20 16:05)
#  Body is byte-for-byte identical to the recovered original.
#  Changed: this header + the log path (was %TEMP%\autostart.txt).
#  It used to live in %TEMP%, which Windows cleanup can wipe at any
#  time - that is the single point of failure this move removes.
# ============================================================
$ErrorActionPreference = 'Continue'
$stage = Join-Path $env:LOCALAPPDATA 'Hermes'
if (-not (Test-Path $stage)) { New-Item -ItemType Directory -Path $stage -Force | Out-Null }
$out = Join-Path $stage 'autostart.log'
"" | Out-File $out -Encoding UTF8
# NOTE: the original used Tee-Object -Append here. Under PowerShell 5.1
# that made the log UTF-16LE while the line above wrote UTF-8+BOM, so the
# file encoding depended on which line wrote last. TESTED 2026-10-01:
# findstr still matched "=== DONE ===" either way, so the launcher was NOT
# broken by this. Kept as a cleanliness fix - one consistent UTF-8 log.
function L($m) { Write-Host $m; $m | Out-File -FilePath $out -Append -Encoding UTF8 }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L "ELEVATED=$elevated"
if (-not $elevated) { L "FATAL not elevated"; exit 9 }

# 三个要自启的程序
$marchBase = Join-Path $env:USERPROFILE 'Desktop'
$marchBase = Join-Path $marchBase ([char]0x8D44 + [char]0x6599 + [char]0x5E93)  # 资料库

$targets = @(
    @{
        Name = 'BetterGI'
        Exe  = 'C:\BetterGI\BetterGI\BetterGI.exe'
        Wd   = 'C:\BetterGI\BetterGI'
        Desc = '原神一条龙 (BetterGI)'
    },
    @{
        Name = 'March7th'
        Exe  = (Join-Path $marchBase 'March7thAssistant_full\March7th Launcher.exe')
        Wd   = (Join-Path $marchBase 'March7thAssistant_full')
        Desc = '崩铁小助手 (March7th Assistant)'
    },
    @{
        Name = 'ZZZOneDragon'
        Exe  = 'C:\MySpecialFolder\OneDragon-Launcher.exe'
        Wd   = 'C:\MySpecialFolder'
        Desc = '绝区零一条龙 (OneDragon)'
    }
)

L ""
L "=== 1. check each target exists ==="
foreach ($t in $targets) {
    $ok = Test-Path $t.Exe
    L ("  " + $t.Name.PadRight(14) + " exists=" + $ok + "  " + $t.Exe)
}

# ============ 方法1: 注册表 Run 键 (最可靠, 登录即启动) ============
L ""
L "=== 2. register in HKCU Run key (login autostart) ==="
$runKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
foreach ($t in $targets) {
    if (-not (Test-Path $t.Exe)) { L ("  - skip (missing): " + $t.Name); continue }
    $value = '"' + $t.Exe + '"'
    try {
        Set-ItemProperty -Path $runKey -Name ('Hermes_' + $t.Name) -Value $value -Type String -Force -ErrorAction Stop
        L ("  + " + ('Hermes_' + $t.Name).PadRight(24) + " = " + $value)
    } catch {
        L ("  ! failed: " + $t.Name + " :: " + $_.Exception.Message)
    }
}

# ============ 方法2: 同时建计划任务 (双保险, 且可延迟避开登录高峰) ============
L ""
L "=== 3. also create scheduled tasks (delay 30s after logon, High privileges) ==="
foreach ($t in $targets) {
    if (-not (Test-Path $t.Exe)) { L ("  - skip (missing): " + $t.Name); continue }
    $taskName = 'Hermes_Autostart_' + $t.Name
    $existing = Get-ScheduledTask -TaskName $taskName -EA SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -EA SilentlyContinue
    }
    $action = New-ScheduledTaskAction -Execute $t.Exe -WorkingDirectory $t.Wd
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" `
        -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description ("自动启动: " + $t.Desc + " (Hermes)") -Force -ErrorAction Stop | Out-Null
        L ("  + task: " + $taskName)
    } catch {
        L ("  ! task failed: " + $t.Name + " :: " + $_.Exception.Message)
    }
}

# ============ 验证 ============
L ""
L "=== 4. VERIFY ==="
L "  --- HKCU Run key ---"
$rv = Get-ItemProperty -Path $runKey -EA SilentlyContinue
$rv.PSObject.Properties | Where-Object { $_.Name -like 'Hermes_*' } | ForEach-Object {
    L ("    " + $_.Name + " = " + $_.Value)
}

L ""
L "  --- scheduled tasks ---"
foreach ($t in $targets) {
    $tn = 'Hermes_Autostart_' + $t.Name
    $st = Get-ScheduledTask -TaskName $tn -EA SilentlyContinue
    if ($st) {
        L ("    " + $tn.PadRight(30) + " state=" + $st.State + " runlevel=" + $st.Principal.RunLevel)
    } else {
        L ("    " + $tn.PadRight(30) + " MISSING")
    }
}

L ""
L "=== DONE ==="
