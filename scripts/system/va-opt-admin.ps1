#Requires -RunAsAdministrator
# 日志跟脚本放一起(原来写死在 Desktop\,归档后重跑会在桌面重新生成一个日志)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$log = Join-Path $scriptDir 'va-opt-log.txt'
Set-Content -Path $log -Value ('=== ' + (Get-Date) + ' ===') -Encoding utf8
function Log($m) { Add-Content -Path $log -Value $m -Encoding utf8 }
function Try-Set { param($Label,[scriptblock]$Action)
  try { & $Action; Log ('[OK]   ' + $Label) }
  catch { Log ('[SKIP] ' + $Label + ' -> ' + $_.Exception.Message) } }

$NIC = (Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Realtek.*2\.5GbE' } | Select-Object -First 1).Name
Log ('NIC = ' + $NIC)

Log '--- 1. 关闭网卡省电/节能特性 ---'
$off = @{ EnableGreenEthernet=0; GigaLite=0; PowerSavingMode=0; AdvancedEEE=0; '*EEE'=0; '*SelectiveSuspend'=0 }
foreach ($kv in $off.GetEnumerator()) { Try-Set ('adv ' + $kv.Key + '=' + $kv.Value) {
  Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword $kv.Key -RegistryValue $kv.Value -ErrorAction Stop } }

Log '--- 2. 取消允许计算机关闭此设备 ---'
Try-Set 'AllowComputerToTurnOffDevice=0' {
  $pnp = (Get-NetAdapter -Name $NIC).PnPDeviceID
  $d = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable | Where-Object { $_.InstanceName -like ('*' + $pnp + '*') }
  if (-not $d) { throw 'MSPower_DeviceEnable 实例未找到' }
  $d | Set-CimInstance -Property @{ Enable = $false } -ErrorAction Stop }

Log '--- 3. 关闭流控制 / LSO, RSS 队列调大 ---'
$off2 = @{ '*FlowControl'=0; '*LsoV2IPv4'=0; '*LsoV2IPv6'=0 }
foreach ($kv in $off2.GetEnumerator()) { Try-Set ('adv ' + $kv.Key + '=' + $kv.Value) {
  Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword $kv.Key -RegistryValue $kv.Value -ErrorAction Stop } }
Try-Set 'adv *NumRssQueues=4' { Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword '*NumRssQueues' -RegistryValue 4 -ErrorAction Stop }

Log '--- 4. TCP 全局 ---'
Try-Set 'rsc=disabled' { netsh int tcp set global rsc=disabled | Out-Null }
Try-Set 'heuristics=disabled' { netsh int tcp set heuristics disabled | Out-Null }

Log '--- 5. 开启游戏模式 ---'
Try-Set 'AutoGameModeEnabled=1' { Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 1 -Type DWord }

Log '--- 6. 关闭快速启动 ---'
Try-Set 'HiberbootEnabled=0' { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord }

Log '--- 7. 禁用第三方虚拟网卡 ---'
foreach ($n in @('Radmin VPN','以太网 2','LetsTAP')) {
  Try-Set ('disable ' + $n) { Disable-NetAdapter -Name $n -Confirm:$false -ErrorAction Stop } }
Try-Set 'disconnect WSL 服务(非必需则保持)' { $null }

Log '--- 8. 游戏内 NVIDIA Reflex 改为 开+Boost ---'
$cfg = 'C:\Tencent Games\VALORANT\live\ShooterGame\Saved\Config\67b36a4d-7fec-5f16-a7c2-5745da055229-alpha1\Windows\RiotUserSettings.ini'
Try-Set 'Reflex=2' {
  Copy-Item $cfg ($cfg + '.bak-reflex') -Force
  $b = [IO.File]::ReadAllBytes($cfg)
  $bom = ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191)
  $t = [IO.File]::ReadAllText($cfg)
  $t2 = $t -replace 'NvidiaReflexLowLatencySetting=\d+','NvidiaReflexLowLatencySetting=2'
  [IO.File]::WriteAllText($cfg, $t2, (New-Object Text.UTF8Encoding($bom)))
  Log ('  bom=' + $bom + '  changed=' + ($t -ne $t2)) }

Log ''
Log '--- 最终状态 ---'
Log '[路由 0.0.0.0/0]'
(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias,NextHop,RouteMetric,InterfaceMetric | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { Log $_ }
Log '[网卡]'
(Get-NetAdapter | Select-Object Name,Status | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { Log $_ }
Log '[网卡高级属性]'
(Get-NetAdapterAdvancedProperty -Name $NIC | Select-Object RegistryKeyword,RegistryValue | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { Log $_ }
Log '[Reflex 行]'
(Select-String -Path $cfg -Pattern 'Reflex' | ForEach-Object { $_.Line }) | ForEach-Object { Log $_ }
Log '=== DONE ==='
