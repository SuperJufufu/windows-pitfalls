# ============================================================
#  RECOVERED 2026-10-01 from  %TEMP%\purge_sc2.ps1  (2026-09-20 16:31)
#  Body is byte-for-byte identical to the recovered original.
#  Changed: this header + the log path (was %TEMP%\purge_sc2.txt).
#  Also recovered for reference: rebuild-icons-reference.ps1
#  The original launcher looked for purge_v5.ps1 in %TEMP% - that file
#  is gone for good, so this script now lives beside the .bat instead
#  of in TEMP, where Windows cleanup deletes it without warning.
# ============================================================
$ErrorActionPreference = 'Continue'
$stage = Join-Path $env:LOCALAPPDATA 'Hermes'
if (-not (Test-Path $stage)) { New-Item -ItemType Directory -Path $stage -Force | Out-Null }
$out = Join-Path $stage 'purge-miner.log'
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

# ---------- 1. QUARANTINE (move to a holding folder before deleting) ----------
$qroot = 'C:\Quarantine_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $qroot -Force | Out-Null
L ("quarantine dir: " + $qroot)

L ""
L "=== 1. move ScreenConnect install dir to quarantine ==="
$sc = 'C:\Program Files (x86)\Windows VC'
if (Test-Path $sc) {
    try {
        Move-Item -Path $sc -Destination (Join-Path $qroot 'Windows VC') -Force -ErrorAction Stop
        L "  moved OK"
    } catch {
        L ("  move failed: " + $_.Exception.Message + " -- trying hard delete")
        Remove-Item -Path $sc -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $sc) { L "  STILL PRESENT" } else { L "  deleted" }
    }
} else { L "  already gone" }

L ""
L "=== 2. move cookie-stealer dir to quarantine ==="
$ck = 'C:\ProgramData\C5FDA2BD'
if (Test-Path $ck) {
    try {
        Move-Item -Path $ck -Destination (Join-Path $qroot 'C5FDA2BD') -Force -ErrorAction Stop
        L "  moved OK"
    } catch {
        L ("  move failed: " + $_.Exception.Message)
        Remove-Item -Path $ck -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $ck) { L "  STILL PRESENT" } else { L "  deleted" }
    }
} else { L "  already gone" }

# ---------- 3. sweep persistence: services ----------
L ""
L "=== 3. sweep services pointing at the malware ==="
$badPatterns = 'Windows VC|ScreenConnect|C5FDA2BD|RuntimeHost|proxies-peer'
Get-CimInstance Win32_Service -EA SilentlyContinue | ForEach-Object {
    $p = $_.PathName
    if ($p -and ($p -match $badPatterns)) {
        L ("  SERVICE: " + $_.Name + "  state=" + $_.State + "  start=" + $_.StartMode)
        L ("     path: " + $p)
        if ($_.State -eq 'Running') {
            try { Stop-Service -Name $_.Name -Force -EA Stop; L "     stopped" } catch { L ("     stop fail: " + $_.Exception.Message) }
        }
        $r = & sc.exe delete $_.Name 2>&1
        L ("     delete -> " + ($r -join ' '))
    }
}

# ---------- 4. sweep scheduled tasks ----------
L ""
L "=== 4. sweep scheduled tasks ==="
Get-ScheduledTask -EA SilentlyContinue | ForEach-Object {
    $acts = ($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($acts -match $badPatterns) {
        L ("  TASK: " + $_.TaskPath + $_.TaskName + "  (" + $acts + ")")
        try {
            Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -EA Stop
            L "     removed"
        } catch { L ("     remove fail: " + $_.Exception.Message) }
    }
}

# ---------- 5. sweep Run keys (all hives) ----------
L ""
L "=== 5. sweep Run keys ==="
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)
foreach ($rk in $runKeys) {
    if (-not (Test-Path $rk)) { continue }
    $props = Get-ItemProperty -Path $rk -EA SilentlyContinue
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        if ($p.Value -match $badPatterns) {
            L ("  " + $rk + " :: " + $p.Name + " = " + $p.Value)
            Remove-ItemProperty -Path $rk -Name $p.Name -Force -EA SilentlyContinue
            L "     removed"
        }
    }
}

# also HKU default / S-1-5-18 (loaded hive)
L ""
L "  --- HKU hives (loaded default/SYSTEM) ---"
foreach ($sub in '\\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Run',
                 '\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Run') {
    try {
        $regPath = 'Registry::HKEY_USERS' + $sub
        if (Test-Path $regPath) {
            $props = Get-ItemProperty -Path $regPath -EA SilentlyContinue
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                if ($p.Value -match $badPatterns) {
                    L ("  HKU" + $sub + " :: " + $p.Name + " = " + $p.Value)
                    Remove-ItemProperty -Path $regPath -Name $p.Name -Force -EA SilentlyContinue
                    L "     removed"
                }
            }
        }
    } catch { L ("  HKU " + $sub + " access failed: " + $_.Exception.Message) }
}

# ---------- 6. verify ----------
L ""
L "=== 6. VERIFY ==="
L ("  Windows VC dir exists   : " + (Test-Path 'C:\Program Files (x86)\Windows VC'))
L ("  C5FDA2BD dir exists     : " + (Test-Path 'C:\ProgramData\C5FDA2BD'))
$svc = Get-Service -Name 'Microsoft Update Service' -EA SilentlyContinue
L ("  fake service exists     : " + [bool]$svc)
$procs = Get-Process -Name 'ScreenConnect*','ccv','mzcv' -EA SilentlyContinue
L ("  malware processes       : " + $(if ($procs) { ($procs | ForEach-Object { $_.ProcessName }) -join ',' } else { 'none' }))
$conn = Get-NetTCPConnection -RemotePort 8041 -EA SilentlyContinue
L ("  connections to :8041    : " + $(if ($conn) { 'STILL PRESENT' } else { 'none (good)' }))

L ""
L "=== 7. firewall: block the C2 IP + port ==="
foreach ($ip in '198.23.185.237') {
    $rn = "Block_MalwareC2_$ip"
    Get-NetFirewallRule -DisplayName $rn -EA SilentlyContinue | Remove-NetFirewallRule -EA SilentlyContinue
    try {
        New-NetFirewallRule -DisplayName $rn -Direction Outbound -RemoteAddress $ip -Action Block -Profile Any -Enabled True -EA Stop | Out-Null
        L ("  blocked outbound -> " + $ip)
    } catch { L ("  block failed: " + $_.Exception.Message) }
}
$rn2 = 'Block_MalwareC2_Port8041'
Get-NetFirewallRule -DisplayName $rn2 -EA SilentlyContinue | Remove-NetFirewallRule -EA SilentlyContinue
try {
    New-NetFirewallRule -DisplayName $rn2 -Direction Outbound -RemotePort 8041 -Protocol TCP -Action Block -Profile Any -Enabled True -EA Stop | Out-Null
    L "  blocked outbound TCP/8041"
} catch { L ("  port block failed: " + $_.Exception.Message) }

L ""
L ("quarantine kept at: " + $qroot)
L "=== DONE ==="
