@echo off
title komorebi - remove from startup
REM  Removes the logon scheduled task and the watchdog, so komorebi will no
REM  longer start when Windows boots. It does NOT stop the running session.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-service.ps1" -Action uninstall
echo.
echo Press any key to close...
pause >nul
