@echo off
title komorebi - repair whkdrc
REM  Rewrites whkdrc in the exact form whkd accepts: no BOM, LF endings,
REM  ASCII only, a bare `.shell` name (cmd / powershell / pwsh - whkd 0.2.10
REM  panics with "could not load whkdrc" on anything else).
REM  Surviving bindings are kept; a backup is written next to the file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0repair-whkdrc.ps1"
echo.
echo Press any key to close...
pause >nul
