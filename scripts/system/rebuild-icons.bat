@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Rebuild Icon Cache

set "DELCOUNT=0"
set "CLEAN_THUMB=0"
if /i "%~1"=="thumb" set "CLEAN_THUMB=1"

echo.
echo  ==================================================
echo    REBUILD ICON CACHE
echo  ==================================================
echo.
echo   Symptom : all desktop / folder icons turned blank
echo   Cause   : corrupted icon cache (IconCache.db)
echo   Fix     : delete the cache, let Windows rebuild it
echo.
echo   This script will:
echo     [1] stop explorer.exe    (taskbar blinks, ~5 sec)
echo     [2] delete icon cache    (regenerated automatically)
echo     [3] restart explorer.exe
echo.
echo   It will NOT touch : your files, shortcuts, settings
echo   Admin rights      : NOT required
if "%CLEAN_THUMB%"=="1" echo   Extra             : thumbnail cache will also be cleared
echo.
echo   TIP: to also clear thumbnail cache, run:  rebuild-icons.bat thumb
echo.
pause
echo.

if not defined LOCALAPPDATA (
  echo [ERROR] LOCALAPPDATA is not defined. Aborting.
  echo.
  pause
  exit /b 1
)

set "ICONDIR=%LOCALAPPDATA%\Microsoft\Windows\Explorer"
set "IDXDB=%LOCALAPPDATA%\IconCache.db"

echo [1/3] Stopping explorer.exe ...
taskkill /f /im explorer.exe >nul 2>&1
set /a TRY=0
:waitkill
tasklist /fi "imagename eq explorer.exe" 2>nul | find /i "explorer.exe" >nul
if not errorlevel 1 (
  set /a TRY+=1
  if !TRY! lss 10 (
    timeout /t 1 /nobreak >nul
    goto waitkill
  )
)
if !TRY! geq 10 echo       [WARN] explorer did not exit within 10s - continuing anyway.
echo       explorer stopped.
echo.

echo [2/3] Deleting icon cache files ...
call :delcache "%IDXDB%"
call :delcache "%ICONDIR%\iconcache_16.db"
call :delcache "%ICONDIR%\iconcache_32.db"
call :delcache "%ICONDIR%\iconcache_48.db"
call :delcache "%ICONDIR%\iconcache_96.db"
call :delcache "%ICONDIR%\iconcache_256.db"
call :delcache "%ICONDIR%\iconcache_768.db"
call :delcache "%ICONDIR%\iconcache_1280.db"
call :delcache "%ICONDIR%\iconcache_1920.db"
call :delcache "%ICONDIR%\iconcache_2560.db"
call :delcache "%ICONDIR%\iconcache_idx.db"
call :delcache "%ICONDIR%\iconcache_custom_stream.db"
call :delcache "%ICONDIR%\iconcache_exif.db"
call :delcache "%ICONDIR%\iconcache_sr.db"
call :delcache "%ICONDIR%\iconcache_wide.db"
call :delcache "%ICONDIR%\iconcache_wide_alternate.db"
if "%CLEAN_THUMB%"=="1" (
  call :delcache "%ICONDIR%\thumbcache_16.db"
  call :delcache "%ICONDIR%\thumbcache_32.db"
  call :delcache "%ICONDIR%\thumbcache_48.db"
  call :delcache "%ICONDIR%\thumbcache_96.db"
  call :delcache "%ICONDIR%\thumbcache_256.db"
  call :delcache "%ICONDIR%\thumbcache_768.db"
  call :delcache "%ICONDIR%\thumbcache_1280.db"
  call :delcache "%ICONDIR%\thumbcache_1920.db"
  call :delcache "%ICONDIR%\thumbcache_2560.db"
  call :delcache "%ICONDIR%\thumbcache_idx.db"
  call :delcache "%ICONDIR%\thumbcache_custom_stream.db"
  call :delcache "%ICONDIR%\thumbcache_exif.db"
  call :delcache "%ICONDIR%\thumbcache_sr.db"
  call :delcache "%ICONDIR%\thumbcache_wide.db"
  call :delcache "%ICONDIR%\thumbcache_wide_alternate.db"
)
echo       deleted: !DELCOUNT! file(s)
echo.

echo [3/3] Restarting explorer.exe ...
start "" explorer.exe
timeout /t 3 /nobreak >nul
if exist "%SystemRoot%\System32\ie4uinit.exe" (
  ie4uinit.exe -show >nul 2>&1
)
echo       explorer restarted, icons refreshed.
echo.

echo  ==================================================
echo    DONE
echo  ==================================================
echo.
echo   If icons are still blank:
echo     1. press F5 on the desktop
echo     2. wait 1-2 minutes (Windows rebuilds lazily)
echo     3. re-run this script with:  rebuild-icons.bat thumb
echo     4. if it STILL fails, check display scaling and
echo        any "optimizer / cleaner" tool that touched
echo        the registry key:
echo        HKCU\Software\Microsoft\Windows\CurrentVersion\
echo             Policies\Explorer
echo.
echo   Nothing was lost - delete this file when done.
echo.
pause
exit /b 0

:delcache
if not exist "%~1" exit /b 0
del /f /q "%~1" >nul 2>&1
if not exist "%~1" (
  set /a DELCOUNT+=1
  echo       - %~nx1
) else (
  echo       [WARN] locked, not deleted: %~nx1
)
exit /b 0
