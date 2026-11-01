#Requires -RunAsAdministrator
$inf = 'D:\DirMove\Downloads\_rtl_lan\realtek_pcielan_10.79.50.1003\WIN10\64\rt640x64.inf'
# 日志跟脚本放一起(原来写死在 Desktop\,归档后重跑会在桌面重新生成一个日志)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$log = Join-Path $scriptDir 'rtl-install-log.txt'
function L($m) { Add-Content -Path $log -Value $m -Encoding utf8 }
Set-Content -Path $log -Value ('=== ' + (Get-Date) + ' ===') -Encoding utf8
L '--- BEFORE ---'
(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match '2.5GbE' } | Select-Object DeviceName,DriverVersion,DriverDate | Format-List | Out-String) -split "`r?`n" | ForEach-Object { L $_ }
L '--- cat 签名 ---'
L ('cat status: ' + (Get-AuthenticodeSignature 'D:\DirMove\Downloads\_rtl_lan\realtek_pcielan_10.79.50.1003\WIN10\64\rt640x64.cat').Status)
L '--- pnputil /add-driver /install ---'
$o = & pnputil.exe /add-driver $inf /install 2>&1
$o | ForEach-Object { L ('  ' + $_) }
L ('exitcode=' + $LASTEXITCODE)
L '--- AFTER ---'
(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match '2.5GbE' } | Select-Object DeviceName,DriverVersion,DriverDate | Format-List | Out-String) -split "`r?`n" | ForEach-Object { L $_ }
L ''
L '--- 重新应用网卡低延迟属性(新驱动可能重置为默认) ---'
$nic = (Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'Realtek.*2.5GbE' } | Select-Object -First 1).Name
$set = @{ '*EEE'=0; AdvancedEEE=0; EnableGreenEthernet=0; GigaLite=0; PowerSavingMode=0; '*SelectiveSuspend'=0; '*FlowControl'=0; '*LsoV2IPv4'=0; '*LsoV2IPv6'=0; '*NumRssQueues'=4; '*InterruptModeration'=0 }
foreach ($kv in $set.GetEnumerator()) {
  try { Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword $kv.Key -RegistryValue $kv.Value -ErrorAction Stop; L ('  [OK] ' + $kv.Key) }
  catch { L ('  [SKIP] ' + $kv.Key + ' : ' + $_.Exception.Message) } }
L '--- 最终高级属性 ---'
(Get-NetAdapterAdvancedProperty -Name $nic | Select-Object RegistryKeyword,RegistryValue | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { L $_ }
L '--- 网卡/路由 ---'
(Get-NetAdapter | Select-Object Name,Status,LinkSpeed | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { L $_ }
(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias,NextHop,RouteMetric,InterfaceMetric | Format-Table -AutoSize | Out-String) -split "`r?`n" | ForEach-Object { L $_ }
L '=== DONE ==='
