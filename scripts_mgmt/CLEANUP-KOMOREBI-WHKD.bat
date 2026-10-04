@echo off
title komorebi + whkd - cleanup leftover config
REM ============================================================
REM  CLEANUP-KOMOREBI-WHKD.bat
REM  Run AFTER UNINSTALL-KOMOREBI-WHKD.bat. Deletes every config
REM  file, scheduled task, PATH entry and helper binary that
REM  komorebi/whkd left behind. Nothing is recoverable after this.
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-komorebi-whkd.ps1"
echo.
echo Press any key to close...
pause >nul
