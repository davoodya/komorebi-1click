@echo off
title komorebi - restart whkd only
REM  Restarts whkd only (e.g. after editing whkdrc hotkeys).
REM  Watchdog-safe: the watchdog is frozen for the restart window.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-whkd.ps1"
echo.
echo Press any key to close...
pause >nul
