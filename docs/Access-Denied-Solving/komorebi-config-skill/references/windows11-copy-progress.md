# Windows 11 Copy/Cut/Delete Progress Dialogs

## Problem

In Windows 11, the copy/cut/delete progress indicator is NOT a separate window.
It is rendered inside the Explorer window itself (title bar + taskbar).
This means `ignore_rules` with `Class` or `Title` cannot match it, because
there is no separate window to match.

## What was tried (all failed to produce a probeable window)

- `cmd copy` with files from 200MB to 20GB
- `robocopy` with and without `/NFL /NDL /NJH /NJS`
- `xcopy`
- `Copy-Item` in PowerShell
- `Shell.Application` COM object
- `SHFileOperation` API
- Background `robocopy`

None of these produced a separate progress window that could be probed.

## Rules added (precautionary)

Even though the progress indicator is part of Explorer, the following rules
were added to `ignore_rules` as a precautionary measure:

```json
{"kind": "Class", "id": "DirectUIHWND"},
{"kind": "Class", "id": "OperationProgressDialog"},
{"kind": "Title", "id": "Copying"},
{"kind": "Title", "id": "Moving"},
{"kind": "Title", "id": "Deleting"}
```

These rules will match IF a separate progress window ever appears (e.g. in
future Windows versions or specific scenarios). They do not affect Explorer
itself because Explorer's class is `CabinetWClass`, not `DirectUIHWND`.

## Implication

If the user wants copy/cut/delete progress to be ignored by Komorebi,
the approach must be different from adding an `ignore_rules` entry.
Possible alternatives:
- Use `floating_applications` to make the Explorer window float during copy
- Use a custom layout that accommodates the progress indicator
- Accept that the progress indicator is part of the Explorer window and cannot be separated

## Recommendation

Before attempting to fix this, verify whether the progress indicator is actually
a separate window or part of the Explorer window. If it is part of the
Explorer window, report this constraint to the user and discuss alternatives.

Do NOT spend hours trying to trigger a progress dialog — if it does not appear
after 2-3 attempts, try a different approach or report the blocker.
