Ticket 04 (eight tabs) — runtime UI verification over UI Automation
====================================================================

Run:      2026-10-10, session 7
Binary:   releases/rust/KomorebiDashboard.exe
          sha256 8ea3c3d1fe18ee4f...
Built by: src/KomorebiDashboardRust/build.ps1 (four phases, exit 0)
Script:   tests/.build/uia-ticket04-eight-tabs.ps1 (scratch; rerun freely)

Method:   the shell is launched, the window is found by pid, the accessibility
          tree is walked once and queried in memory. Measured UI fact: the
          strip's role="tab" buttons surface as ControlType.TabItem (not
          Button) and are driven with SelectionItemPattern; the verb action
          buttons are ControlType.Button with InvokePattern.

Ticket 04 — eight tabs in the rendered window (2026-10-10T14:47:30.5189990+03:30)
PASS  A1 exactly eight tabs, backend order  found: Kill and Start > Restart and Reloading > Settings > Customization > AutoHotkey Scripts > Debugging > Uninstall and Cleanup > About
PASS  A2 opens on Kill and Start
PASS  A2 first tab marked selected
PASS  A3 Debugging panel description
PASS  A3 Debugging rows
PASS  A3 selection moved to Debugging
PASS  A3 selection left Kill and Start
PASS  A4 status run verdict  console at 32 lines
PASS  A5 empty row state on About
PASS  A5 About description
PASS  A5 console line count unchanged  before=32 after=32
PASS  A6 verdict survives the switch
RESULT: 12 passed, 0 failed

What each assertion proves against the ticket's boxes
-----------------------------------------------------
A1  box 1 — all eight tabs render, drawn from the backend's own tab list in
    the backend's order, with nothing added and none hidden.
A2  box 1 — the panel opens on the first declared tab with its description,
    and the strip marks it selected (the fallback for "nothing picked yet").
A3  boxes 1+6 — selecting a tab re-renders the panel from that tab's own rows
    (the Debugging rows appear, the previous tab's rows do not), and the
    selection state moves to the chosen tab and leaves the old one.
A4  box 6 setup — a read-only verb run reaches the console and finishes with
    an exit-0 verdict, so there is accumulated output to preserve.
A5  boxes 1+6 — the About tab (a hand-built surface with no registry verbs)
    renders the empty row state instead of a broken grouping, and the console
    line count is identical across the switch (32 -> 32): the transcript is
    neither cleared nor re-rendered.
A6  box 6 — the finished verdict and its output survive the switch.

Not asserted here (covered elsewhere): the READ-ONLY badge (box 3) and the
numeric filter (box 4) are row-component behaviour pinned by the frontend unit
tests (src/tests/format.spec.ts, filterNumericValue) and unchanged for every
tab because one shared VerbRow renders all of them; the per-row current value
(box 5) is the row's own value box, owned per row (src/tests/rows.spec.ts).
