@echo off
chcp 65001 >nul
setlocal
title Fix blank shortcut icons - folder integrity label

rem ============================================================
rem  FIX BLANK SHORTCUT ICONS
rem
rem  Resets the Desktop / Favorites folder integrity label from
rem  "Low" back to "Medium".
rem
rem  Symptom this fixes:
rem    Every .lnk on the desktop shows a blank page with a small
rem    arrow. Folders, .exe and .png files look normal. The same
rem    shortcut copied to another folder shows its real icon.
rem    Rebuilding the icon cache changes nothing.
rem
rem  Cause: an agent sandbox labelled the folder Low integrity so
rem  that sandboxed processes could write there. Windows will not
rem  resolve shortcut icons inside a Low integrity folder.
rem
rem  Needs administrator rights - it self-elevates.
rem  Safe to re-run any time.
rem ============================================================

net session >nul 2>&1
if errorlevel 1 goto elevate
goto run

:elevate
echo.
echo  Administrator rights are required.
echo  A UAC prompt will appear - please click Yes.
echo.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:run
echo.
echo  ============================================================
echo    FIX BLANK SHORTCUT ICONS  -  reset integrity label
echo  ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-icon-label.ps1"
echo.
pause
