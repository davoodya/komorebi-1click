@echo off
title komorebi - reset workspaces to 1..9 on every monitor
REM  Reorders the workspace vector so every monitor shows 1,2,3,...,9 again.
REM  retile does NOT do this - only a full stop/start does.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reset-workspaces.ps1"
echo.
echo Press any key to close...
pause >nul
