# ============================================================
#  fix-icon-label.ps1
#
#  Resets folder integrity labels to Medium.
#
#  WHY: an agent sandbox (DSH / Codex) labels the Desktop folder as
#  "Low Mandatory Level" so that low-integrity sandboxed processes
#  can write there. Windows then REFUSES to resolve .lnk (shortcut)
#  icons inside a Low-integrity folder, so every shortcut renders as
#  a blank page with an arrow - while folders, .exe, .png and files
#  in other folders stay fine.
#
#  Deleting the icon cache does NOT help. desktop.ini is not involved.
#  Bags/BagMRU are not involved. The folder's integrity label IS the
#  cause (verified by reproducing it on a test folder).
#
#  This is invoked by fix-icon-label.bat, which self-elevates.
# ============================================================

$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '=== Reset folder integrity labels to Medium ==='
Write-Host ''

# --- build the target list -------------------------------------------
$targets = New-Object System.Collections.ArrayList
[void]$targets.Add((Join-Path $env:USERPROFILE 'Desktop'))
[void]$targets.Add((Join-Path $env:USERPROFILE 'Favorites'))

# scan the user profile for any other Low-labeled folder
Get-ChildItem $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $t = (cmd /c "icacls `"$($_.FullName)`"" 2>&1) | Select-String 'Low Mandatory'
    if ($t) { if (-not $targets.Contains($_.FullName)) { [void]$targets.Add($_.FullName) } }
}

# --- fix -------------------------------------------------------------
$fixed = 0
$failed = 0
foreach ($p in $targets) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "  skip (missing)     : $p"
        continue
    }
    $before = ((cmd /c "icacls `"$p`"" 2>&1) | Select-String 'Mandatory Label') -join ''
    if ($before -notmatch 'Low') {
        Write-Host "  already Medium     : $p"
        continue
    }
    Write-Host "  Low integrity found: $p"
    $out = cmd /c "icacls `"$p`" /setintegritylevel (OI)(CI)Medium" 2>&1
    $after = ((cmd /c "icacls `"$p`"" 2>&1) | Select-String 'Mandatory Label') -join ''
    if ($after -match 'Low') {
        Write-Host "     -> FAILED. Output: $out" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "     -> fixed (now Medium)." -ForegroundColor Green
        $fixed++
    }
}

Write-Host ''
Write-Host "=== $fixed folder(s) fixed, $failed failed ==="
Write-Host ''
Write-Host 'Icons usually come back within ~30 seconds.'
Write-Host 'Press F5 on the desktop if it still looks stale.'
Write-Host 'If icons are still blank after that, sign out and back in.'
Write-Host ''
