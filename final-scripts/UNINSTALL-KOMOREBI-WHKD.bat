@echo off
title komorebi + whkd - uninstall
REM ============================================================
REM  UNINSTALL-KOMOREBI-WHKD.bat
REM  Removes the komorebi + whkd SOFTWARE (binaries) and stops
REM  everything. Your config files are NOT touched - run
REM  CLEANUP-KOMOREBI-WHKD.bat afterwards if you want those gone
REM  too.
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-komorebi-whkd.ps1"
echo.
echo Press any key to close...
pause >nul
