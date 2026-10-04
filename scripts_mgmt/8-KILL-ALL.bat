@echo off
title komorebi - kill all services
REM  Stops komorebi + whkd + yasb. Windows are left in place.
REM  The watchdog will NOT bring them back - use 9-START-ALL.bat to restart.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kill-all.ps1"
echo.
echo Press any key to close...
pause >nul
