@echo off
title komorebi - import config
REM  Restores the config from F:\Backups\Software-Backups\komorebi-whkd\config
REM  The current live config is saved to a pre-import-<timestamp> folder first,
REM  so this is always reversible. Stops the WM, restores, starts it again.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-backup.ps1" -Mode import
echo.
echo Press any key to close...
pause >nul
