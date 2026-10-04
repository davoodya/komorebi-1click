@echo off
title AutoHotkey - remove the leftover startup and state
REM  Removes the generated AppRunner.vbs, the enable/disable state file, and
REM  any process running a script from this repo's autohotkey\ directory.
REM  The interpreters stay installed; use AHK-UNINSTALL.bat for those.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ahk-cleanup.ps1"
echo.
echo Press any key to close...
pause >nul
