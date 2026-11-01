# 彻底清理 Windows 图标缓存
# 需要：停 explorer → 删缓存 → 重启 explorer

Write-Host "=== 1. 停掉资源管理器 ==="
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Host "=== 2. 删除所有图标缓存 ==="
$paths = @(
    (Join-Path $env:LOCALAPPDATA 'IconCache.db'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer')
)
foreach ($p in $paths) {
    if (Test-Path $p -PathType Leaf) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        Write-Host "  removed $p"
    } elseif (Test-Path $p) {
        Get-ChildItem $p -Filter 'iconcache*.db' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "  removed $($_.Name)"
        }
        Get-ChildItem $p -Filter 'thumbcache*.db' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "  removed $($_.Name)"
        }
    }
}

Write-Host "=== 3. 清理 shell 缓存 ==="
$shellCache = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
if (Test-Path $shellCache) {
    Get-ChildItem $shellCache -ErrorAction SilentlyContinue | ForEach-Object {
        # 不动，只报告
    }
}
ie4uinit.exe -show 2>$null
ie4uinit.exe -ClearIconCache 2>$null

Write-Host "=== 4. 重启资源管理器 ==="
Start-Sleep -Seconds 2
Start-Process explorer.exe
Start-Sleep -Seconds 3
$e = Get-Process -Name explorer -ErrorAction SilentlyContinue
if ($e) { Write-Host "  explorer restarted (pid $($e.Id))" } else { Write-Host "  WARNING: explorer not running" }
