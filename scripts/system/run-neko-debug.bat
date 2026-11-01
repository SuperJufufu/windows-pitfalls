@echo off
chcp 65001 >nul
title N.E.K.O. Debug Run (capture console)
cd /d "D:\SteamLibrary\steamapps\common\n.e.k.o"

echo ==========================================
echo   N.E.K.O. DEBUG RUN
echo ==========================================
echo.
echo   This runs N.E.K.O. and saves ALL console
echo   output (including renderer logs) to a file:
echo.
echo     %%USERPROFILE%%\Desktop\neko_console.log
echo.
echo   Use this to check whether the MULTISCREEN
echo   patch is active and whether it stitched.
echo.
echo   Press any key to start (close N.E.K.O. first!)
echo.
pause

set "OUT=%USERPROFILE%\Desktop\neko_console.log"
echo [START] %DATE% %TIME% > "%OUT%"

echo Launching N.E.K.O. with logging...
"N.E.K.O.exe" >> "%OUT%" 2>&1
echo.
echo Done. Log saved to: %OUT%
pause
