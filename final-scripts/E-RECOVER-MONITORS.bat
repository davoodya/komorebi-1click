@echo off
title komorebi - recover monitors
REM  Run this after plugging/unplugging or powering a monitor off/on.
REM  Restores orphaned windows, re-applies display index preferences, retiles.
REM  Read-only for your config files.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0recover-monitors.ps1"
echo.
echo Press any key to close...
pause >nul
