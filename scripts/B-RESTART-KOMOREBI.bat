@echo off
title komorebi - restart komorebi only
REM  Restarts komorebi only (e.g. after editing komorebi.json).
REM  Watchdog-safe: the watchdog is frozen for the restart window so it
REM  cannot double-start komorebi against the same socket.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-komorebi.ps1"
echo.
echo Press any key to close...
pause >nul
