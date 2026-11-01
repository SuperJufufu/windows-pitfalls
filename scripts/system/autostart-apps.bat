@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Autostart: BetterGI / March7th / ZZZ OneDragon

rem ============================================================
rem  Autostart setup for the three game helpers.
rem  Restores the ORIGINAL behaviour, recovered 2026-10-01:
rem    1. HKCU Run key   Hermes_<Name>
rem    2. Scheduled task Hermes_Autostart_<Name>
rem       (at logon, +30s, RunLevel Highest, working dir set)
rem
rem  Usage:
rem    autostart-apps.bat             apply  (asks for 1x UAC)
rem    autostart-apps.bat --status    report only, changes nothing
rem    autostart-apps.bat --remove    undo everything
rem
rem  WHY THIS FILE CHANGED:
rem  It used to run %TEMP%\autostart.ps1. %TEMP% gets cleaned, and the
rem  .ps1 can be wiped at any moment - so the logic now ships beside
rem  this .bat and is staged onto an ASCII path before elevation
rem  (this folder's name is non-ASCII and would be mangled by UAC).
rem ============================================================

set "MODE=apply"
if /i "%~1"=="--status" set "MODE=status"
if /i "%~1"=="--remove" set "MODE=remove"

set "STAGE=%LOCALAPPDATA%\Hermes"
set "SRC=%~dp0autostart-apps.ps1"
set "DST=%STAGE%\autostart-apps.ps1"
set "LOG=%STAGE%\autostart.log"
set "RUNKEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
set "T1=Hermes_Autostart_BetterGI"
set "T2=Hermes_Autostart_March7th"
set "T3=Hermes_Autostart_ZZZOneDragon"

echo.
echo  ==================================================
echo    AUTOSTART SETUP      [mode: %MODE%]
echo  ==================================================
echo.
echo    Targets:
echo      BetterGI      C:\BetterGI\BetterGI\BetterGI.exe
echo      March7th      ...\March7thAssistant_full\March7th Launcher.exe
echo      ZZZOneDragon  C:\MySpecialFolder\OneDragon-Launcher.exe
echo.
echo    Mechanism 1: HKCU Run key         (Hermes_BetterGI ...)
echo    Mechanism 2: scheduled task, +30s (Hermes_Autostart_...)
echo.
if /i "%MODE%"=="status" goto :status
if /i "%MODE%"=="remove" goto :remove

echo  Applying. One UAC prompt will appear - click YES.
echo.
pause
echo.

if not exist "%SRC%" (
  echo  [ERROR] missing: %SRC%
  echo          this launcher needs autostart-apps.ps1 beside itself.
  echo.
  pause
  exit /b 1
)

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

powershell.exe -NoProfile -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%DST%'"

echo  Waiting for the setup to finish ...
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
goto :done

:status
echo  ---- HKCU Run key ----
reg query "%RUNKEY%" 2>nul | findstr /i "Hermes_"
if errorlevel 1 echo    (none)
echo.
echo  ---- scheduled tasks ----
schtasks /query /tn "%T1%" >nul 2>&1 && echo    present: %T1% || echo    absent : %T1%
schtasks /query /tn "%T2%" >nul 2>&1 && echo    present: %T2% || echo    absent : %T2%
schtasks /query /tn "%T3%" >nul 2>&1 && echo    present: %T3% || echo    absent : %T3%
echo.
echo  ---- staged script ----
if exist "%DST%" (echo    %DST%) else (echo    not staged yet)
goto :done

:remove
echo  Removing Run keys ...
for %%N in (Hermes_BetterGI Hermes_March7th Hermes_ZZZOneDragon) do (
  reg delete "%RUNKEY%" /v %%N /f >nul 2>&1
  if errorlevel 1 (echo    [ -- ] %%N not present) else (echo    [ del] %%N)
)
echo.
net session >nul 2>&1
if errorlevel 1 (
  echo  Scheduled tasks need admin - re-run this as administrator:
  echo    right-click autostart-apps.bat  -^>  Run as administrator
) else (
  echo  Removing scheduled tasks ...
  for %%N in ("%T1%" "%T2%" "%T3%") do (
    schtasks /delete /tn %%N /f >nul 2>&1
    if errorlevel 1 (echo    [ -- ] %%~N not present) else (echo    [ del] %%~N)
  )
)
goto :done

:done
echo.
pause
exit /b 0
