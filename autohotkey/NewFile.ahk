#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; NewFile.ahk v3 — Multi-tab File Explorer support
; Hotkey: Ctrl + Win + N
; Creates a new empty file in the CURRENTLY ACTIVE Explorer tab
; (or Desktop) and immediately enters rename mode (exactly like
; Ctrl+Shift+N for New Folder).
;
; Compatible with Komorebi / WHKD (no Alt / no conflicting keys).
; ============================================================

GroupAdd "FileManagers", "ahk_class CabinetWClass" ; Windows Explorer
GroupAdd "FileManagers", "ahk_class TTOTAL_CMD"     ; Total Commander
GroupAdd "FileManagers", "ahk_class WindowClass_1" ; One Commander
GroupAdd "FileManagers", "ahk_class Progman"        ; Desktop
GroupAdd "FileManagers", "ahk_class WorkerW"        ; Desktop (alt)

#HotIf WinActive("ahk_group FileManagers")
^#n:: {
    activeHwnd := WinExist("A")
    currentPath := ""
    explorerWindow := 0   ; will hold the correct Shell.Application window object

    if WinActive("ahk_class Progman") || WinActive("ahk_class WorkerW") {
        ; Desktop
        currentPath := A_Desktop
    } else if WinActive("ahk_class CabinetWClass") {
        ; ---------- Windows 11 multi-tab support ----------
        activeTab := 0
        try activeTab := ControlGetHwnd("ShellTabWindowClass1", "ahk_id " activeHwnd)

        for window in ComObject("Shell.Application").Windows {
            if (window.HWND != activeHwnd)
                continue

            if activeTab {
                ; Filter to the currently active tab only
                static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                try {
                    shellBrowser := ComObjQuery(window, IID_IShellBrowser, IID_IShellBrowser)
                    ComCall(3, shellBrowser, "uint*", &thisTab := 0)  ; GetWindow()
                    if (thisTab != activeTab)
                        continue
                }
            }
            ; Found the correct tab
            explorerWindow := window
            currentPath := window.Document.Folder.Self.Path
            break
        }
    } else {
        ; Other file managers (Total Commander, One Commander, etc.)
        try {
            for window in ComObject("Shell.Application").Windows {
                if (window.HWND == activeHwnd) {
                    currentPath := window.Document.Folder.Self.Path
                    explorerWindow := window
                    break
                }
            }
        }
    }

    if (currentPath == "" || !DirExist(currentPath))
        return

    ; ---- Create unique filename ----
    baseName  := currentPath "\NewFile"
    ext       := ".txt"
    finalPath := baseName ext
    counter   := 2
    while FileExist(finalPath) {
        finalPath := baseName " (" counter ")" ext
        counter++
    }

    ; Create empty UTF-8 file
    FileAppend "", finalPath, "UTF-8"

    ; ---- Refresh + select + rename ----
    if (explorerWindow) {
        try {
            explorerWindow.Refresh()          ; more reliable than F5 for the correct tab
            Sleep(150)

            SplitPath finalPath, &fileName
            item := explorerWindow.Document.Folder.ParseName(fileName)
            if item {
                ; SVSI_FOCUSED | SVSI_SELECT | SVSI_ENSUREVISIBLE
                explorerWindow.Document.SelectItem(item, 1 | 4 | 8)
                Sleep(80)
                Send("{F2}")                 ; enter rename mode
            }
        }
    } else {
        ; Fallback for Desktop / other managers
        Send("{F5}")
        Sleep(150)
        ; Optional: you can add more logic for Desktop if needed
    }
}
#HotIf