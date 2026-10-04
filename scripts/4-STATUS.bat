@echo off
title komorebi - health check
REM  Read-only. Changes nothing. Use it to confirm hotkeys should be working,
REM  and to see exactly what is wrong if they are not.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-service.ps1" -Action status
echo Press any key to close...
pause >nul
