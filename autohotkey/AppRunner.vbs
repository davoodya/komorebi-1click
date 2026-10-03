' ==========================================================================
' AppRunner.vbs  -  startup launcher for the AutoHotkey scripts
' ==========================================================================
' GENERATED at install time by Install.ps1 (ticket 05, ADR-0010). Do not edit
' this copy: the installer regenerates it, and ticket 08's enable/disable
' mechanism rewrites the per-script lines.
'
' One RunHidden line is emitted per shipped script, in a fixed order. Each
' points at the interpreter for the script's AutoHotkey version and at the
' script path under the repository's autohotkey\ directory, so there are no
' machine-specific constants anywhere in this file.
' ==========================================================================

' Run a command with no visible window.
Sub RunHidden(command)
    CreateObject("WScript.Shell").Run command, 0, False
End Sub

' Run a command with a normal window.
Sub RunNormal(command)
    CreateObject("WScript.Shell").Run command, 1, False
End Sub

' === generated lines (do not edit; the installer regenerates this file) ===

' AppRunnerEnd
