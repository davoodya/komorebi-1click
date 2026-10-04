@echo off
title komorebi - export config
REM  Copies the live config into a fresh timestamped folder under
REM  %USERPROFILE%\.config\komorebi-backup-<yyyyMMdd-HHmmss>
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-backup.ps1" -Mode export
echo.
pause
