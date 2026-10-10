# Windows Forms Apps and Komorebi

## Problem

Windows Forms applications (like ShareX) can have rendering issues when
Komorebi resizes them. The window content may appear blank or not render
correctly after a resize.

## Root Cause

Windows Forms uses a custom layout system that does not always respond
correctly to external window resizing. When Komorebi resizes the window,
the internal layout may not be recalculated, leaving the content blank.

## Solution

Add the application to `ignore_rules` in `komorebi.json`:

```json
{"kind": "Exe", "id": "ShareX.exe"}
```

This prevents Komorebi from managing the window at all — no tiling, no
resizing, no floating. The application runs independently.

## Why ignore_rules and not floating_applications?

| Approach | Result |
|---|---|
| `floating_applications` | Window is still **managed** — Komorebi resizes it, content stays blank |
| `ignore_rules` | Window is **not managed** — Komorebi leaves it alone, app renders correctly |

## Verification

After adding the rule and restarting Komorebi:

```powershell
# Check that the window is NOT managed
$komorebic = 'C:\Program Files\komorebi\bin\komorebic.exe'
$state = & $komorebic state | ConvertFrom-Json
# The window should NOT appear in the managed windows list
```

## Other affected apps

Any Windows Forms or similar framework app that shows blank content when
resized by Komorebi should be added to `ignore_rules`. Common examples:
- ShareX
- Older .NET desktop apps
- Some Java Swing apps
