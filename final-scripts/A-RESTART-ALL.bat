@echo off
title komorebi - restart all services
REM  Restarts komorebi + whkd + yasb to apply new configs.
REM  Prefer 0-SAFE-RESTART.bat: it additionally freezes the watchdog and
REM  verifies your tiled layout survived. This is the lighter variant.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-all.ps1"
echo.
echo Press any key to close...
pause >nul
