#Requires -RunAsAdministrator
# 无畏契约/VALORANT 局内延迟优化 - 补完剩余项   (回滚方法见文件末尾)
$ErrorActionPreference = 'Continue'
$NIC = (Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Realtek.*2\.5GbE' -and $_.Status -eq 'Up' } | Select-Object -First 1).Name
if (-not $NIC) { Write-Host '找不到已连接的 Realtek 2.5GbE 网卡'; exit 1 }
Write-Host ('目标网卡: ' + $NIC) -ForegroundColor Green
function Try-Set { param($Label,[scriptblock]$Action)
  try { & $Action; Write-Host ('  [OK]   ' + $Label) -ForegroundColor Green }
  catch { Write-Host ('  [SKIP] ' + $Label + ' -> ' + $_.Exception.Message) -ForegroundColor Yellow } }

Write-Host ''
Write-Host '== 1. 关闭网卡省电/节能特性 ==' -ForegroundColor Cyan
$off = @{ EnableGreenEthernet=0; GigaLite=0; PowerSavingMode=0; AdvancedEEE=0; '*EEE'=0; '*SelectiveSuspend'=0 }
foreach ($kv in $off.GetEnumerator()) { Try-Set ($kv.Key + ' = ' + $kv.Value) {
  Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword $kv.Key -RegistryValue $kv.Value -ErrorAction Stop } }

Write-Host ''
Write-Host '== 2. 降低排队/中断延迟 ==' -ForegroundColor Cyan
$off2 = @{ '*FlowControl'=0; '*LsoV2IPv4'=0; '*LsoV2IPv6'=0 }
foreach ($kv in $off2.GetEnumerator()) { Try-Set ($kv.Key + ' = ' + $kv.Value) {
  Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword $kv.Key -RegistryValue $kv.Value -ErrorAction Stop } }
Try-Set 'RSS 接收队列 2 -> 4' { Set-NetAdapterAdvancedProperty -Name $NIC -RegistryKeyword '*NumRssQueues' -RegistryValue 4 -ErrorAction Stop }

Write-Host '== 3. 禁止系统为省电关闭网卡 ==' -ForegroundColor Cyan
Try-Set '取消 [允许计算机关闭此设备以节约电源]' {
  $pnp = (Get-NetAdapter -Name $NIC).PnPDeviceID
  $d = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable | Where-Object { $_.InstanceName -like ('*' + $pnp + '*') }
  if (-not $d) { throw '未找到 MSPower_DeviceEnable 实例' }
  $d | Set-CimInstance -Property @{ Enable = $false } -ErrorAction Stop }

Write-Host '== 4. TCP 全局: 关闭 RSC ==' -ForegroundColor Cyan
Try-Set 'rsc=disabled'        { netsh int tcp set global rsc=disabled | Out-Null }
Try-Set 'heuristics disabled' { netsh int tcp set heuristics disabled | Out-Null }

Write-Host '== 5. 开启 Windows 游戏模式 (激活已调好的 MMCSS Games 配置) ==' -ForegroundColor Cyan
Try-Set 'AutoGameModeEnabled=1' { Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 1 -Type DWord }

Write-Host '== 6. 关闭快速启动 ==' -ForegroundColor Cyan
Try-Set 'HiberbootEnabled=0' { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord }

Write-Host '== 7. 虚拟网卡体检 (Radmin / 网易UU / WSL) ==' -ForegroundColor Cyan
Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias,NextHop,RouteMetric,InterfaceMetric | Format-Table -AutoSize
Write-Host '  注意: 以太网 的总度量值必须最小, 否则流量会被虚拟网卡劫持' -ForegroundColor DarkGray

Write-Host '== 8. (可选) Defender 排除游戏目录, 需手动取消注释 ==' -ForegroundColor Cyan
# Add-MpPreference -ExclusionPath 'C:\Tencent Games\VALORANT'
# Add-MpPreference -ExclusionProcess 'VALORANT-Win64-Shipping.exe'

Write-Host '完成, 建议重启后再进游戏。' -ForegroundColor Green

<#  ---------- 回滚 ----------
$n = '以太网'
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*FlowControl'      -RegistryValue 3
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*LsoV2IPv4'        -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*LsoV2IPv6'        -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword 'EnableGreenEthernet' -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword 'GigaLite'          -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword 'PowerSavingMode'   -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*SelectiveSuspend' -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword '*NumRssQueues'     -RegistryValue 2
netsh int tcp set global rsc=enabled
netsh int tcp set heuristics enabled
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 0 -Type DWord
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 1 -Type DWord
#>
