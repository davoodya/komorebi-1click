@echo off
REM  Compare Windows' own display geometry with what komorebi computed.
REM  Read-only. Use when 4-STATUS.bat shows a monitor with a negative width.
title komorebi - display diagnostic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0display-diag.ps1"
echo.
pause
