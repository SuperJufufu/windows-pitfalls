@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Miner Purge - click YES on UAC

set "STAGE=%LOCALAPPDATA%\Hermes"
set "SRC=%~dp0purge-miner.ps1"
set "DST=%STAGE%\purge-miner.ps1"
set "LOG=%STAGE%\purge-miner.log"

echo.
echo  ============================================
echo    MINER / SCREENCONNECT PURGE  -  1x UAC
echo  ============================================
echo.
echo    - kills InstallUtil.exe (guardian)
echo    - kills SecurityHealthHost.exe (miner)
echo    - moves ScreenConnect + cookie-stealer dirs
echo    - sweeps services / tasks / Run keys
echo    - blocks C2 198.23.185.237 and TCP/8041
echo.
echo    Deletion is NEVER blind: everything is first MOVED into
echo    C:\Quarantine_^<timestamp^> so it stays recoverable.
echo.
echo    Script body: recovered 2026-10-01 from the 2026-09-20
echo    incident response. Read it yourself if you like:
echo      %SRC%
echo.
pause
echo.

if not exist "%SRC%" (
  echo  [ERROR] missing: %SRC%
  echo          this launcher needs purge-miner.ps1 beside itself.
  echo.
  pause
  exit /b 1
)

rem ------------------------------------------------------------------
rem  The folder this .bat lives in has a NON-ASCII name. Passing a
rem  non-ASCII path across a UAC elevation boundary mangles it, which
rem  is why the original author parked the .ps1 in %TEMP%. That fix
rem  backfired: Windows cleans %TEMP%, so the script vanished and this
rem  launcher died with "script not found". We stage onto an ASCII path
rem  under LOCALAPPDATA instead - survives cleanup AND survives UAC.
rem ------------------------------------------------------------------
if not exist "%STAGE%" mkdir "%STAGE%" >nul 2>&1
copy /y "%SRC%" "%DST%" >nul
if errorlevel 1 (
  echo  [ERROR] could not stage the script to:
  echo          %DST%
  echo.
  pause
  exit /b 1
)
del /f /q "%LOG%" >nul 2>&1

echo  Requesting admin rights - click YES on the UAC prompt...
powershell.exe -NoProfile -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%DST%'"

echo  Waiting for the purge to finish ...
set /a W=0
:waitlog
if exist "%LOG%" (
  findstr /c:"=== DONE ===" "%LOG%" >nul 2>&1 && goto :showlog
)
set /a W+=1
if !W! geq 30 goto :showlog
timeout /t 2 /nobreak >nul
goto :waitlog

:showlog
echo.
if exist "%LOG%" (
  echo  ===== RESULT =====
  type "%LOG%"
) else (
  echo  No log produced - the UAC prompt was probably not approved.
)
echo.
echo  Full log kept at: %LOG%
echo.
pause
exit /b 0
