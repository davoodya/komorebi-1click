@echo off
title komorebi - start all services
REM  Starts komorebi + whkd + yasb (only the ones that are not already running).
REM  komorebi starts first because whkd and yasb talk to its socket.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-all.ps1"
echo.
echo Press any key to close...
pause >nul
