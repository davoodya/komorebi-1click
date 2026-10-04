@echo off
title AutoHotkey - uninstall both versions
REM  Uninstalls AutoHotkey v1 and v2, stops every interpreter process, and
REM  removes the generated startup launcher. The shipped .ahk scripts stay in
REM  the repository.
echo This removes AutoHotkey v1 AND v2 from this machine.
echo The three scripts shipped in this repository are not deleted.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ahk-uninstall.ps1"
echo.
echo Press any key to close...
pause >nul
