@echo off
title komorebi - add to startup
REM  Makes komorebi start automatically every time Windows boots, and installs
REM  a watchdog that restarts it only if it has actually died.
REM  Run this ONCE. Re-running it is harmless.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-service.ps1" -Action install
echo.
echo Press any key to close...
pause >nul
