@echo off
title komorebi - import config
REM  A folder picker opens; choose the komorebi-backup folder to restore.
REM  The current live config is saved to a pre-import-<timestamp> folder first,
REM  so this is always reversible. Stops the WM, restores, starts it again.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-backup.ps1" -Mode import
echo.
echo Press any key to close...
pause >nul
