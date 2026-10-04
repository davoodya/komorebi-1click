@echo off
title yasb - restart and verify
REM  Restarts YASB only, with a registry-fresh PATH so the komorebi event
REM  listener can resolve komorebic.exe, and prints the connection verdict.
REM
REM  A full restart (not a config hot-reload) is required because the running
REM  YASB process inherited its PATH at launch, and watch_config does not
REM  notice edits made from WSL (drvfs).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-yasb.ps1"
echo.
echo Press any key to close...
pause >nul
