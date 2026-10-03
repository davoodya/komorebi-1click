@echo off
REM ===========================================================================
REM restart-whkd.cmd  -  restart whkd so an edited whkdrc takes effect
REM ===========================================================================
REM Called by the whkdrc `alt + o` hotkey. GENERATED at install time: the
REM __KOMOREBIC_EXE__ placeholder below is replaced with this machine's
REM komorebic.exe path. Do not edit this copy, the installer regenerates it.
REM
REM Restarts whkd without leaving a dead-hotkey window: stop komorebi, then
REM start it again with --whkd, which respawns whkd as its child with the
REM freshly parsed whkdrc. whkd dies with komorebi, so this is the
REM vendor-supported single-command restart.
REM
REM whkd 0.2.10 PANICS when one key is bound twice in the same whkdrc, so a
REM single binding has to call a single command that performs both halves.
REM ===========================================================================

"__KOMOREBIC_EXE__" stop
>nul 2>&1 timeout /t 1 /nobreak
"__KOMOREBIC_EXE__" start --whkd
exit /b
