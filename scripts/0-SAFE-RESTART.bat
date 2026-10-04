@echo off
title komorebi - SAFE restart (workspace-safe)
REM  The safe restart. Use this one instead of killing processes or running
REM  a plain `komorebic stop`. It freezes the watchdog for the restart window
REM  (so no double-start race), snapshots and verifies your tiled windows, and
REM  reports the workspace order per monitor afterwards.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0safe-restart.ps1"
echo Press any key to close...
pause >nul
