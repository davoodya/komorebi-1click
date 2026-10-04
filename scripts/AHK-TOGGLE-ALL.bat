@echo off
title AutoHotkey - turn all scripts on or off
REM  Turns every shipped AutoHotkey script to the same state at once.
REM  Usage: AHK-TOGGLE-ALL.bat enabled
REM         AHK-TOGGLE-ALL.bat disabled
if "%~1"=="" (
    echo Usage: AHK-TOGGLE-ALL.bat ^<enabled^|disabled^>
    echo.
    echo Either "enabled" or "disabled" is required.
    echo.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ahk-toggle.ps1" -State "%~1"
echo.
echo Press any key to close...
pause >nul
