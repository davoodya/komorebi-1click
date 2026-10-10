@echo off
title komorebi - export config
REM  A folder picker opens; the folder you choose gets a fresh
REM  komorebi-backup-<yyyyMMdd-HHmmss>\ holding the whole current config.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-backup.ps1" -Mode export
echo.
pause
