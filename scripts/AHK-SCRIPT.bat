@echo off
title AutoHotkey - toggle a script on or off
REM  Lists the shipped AutoHotkey scripts and their state when run with no args.
REM  Usage: AHK-SCRIPT.bat            (list)
REM         AHK-SCRIPT.bat NewFile disabled
REM         AHK-SCRIPT.bat NewFile enabled
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ahk-script.ps1" -List
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ahk-script.ps1" -Name "%~1" -State "%~2"
)
echo.
echo Press any key to close...
pause >nul
