@echo off
title komorebi - export config
REM  Copies the live config into F:\Backups\Software-Backups\komorebi-whkd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0komorebi-backup.ps1" -Mode export
echo.
pause
