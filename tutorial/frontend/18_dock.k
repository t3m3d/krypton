// 18_dock.k — VS-style dock layout.
//
// guiDock is a layout manager that pins child widgets to edges of
// the window. One widget gets `fill` for the leftover middle area.
// Sides eat the window in declaration order — first dockTop is
// closer to the top edge than the second dockTop.
//
// On every WM_SIZE the dock recomputes positions automatically.

import "stdlib/gui.k"


just run {
    guiInit()
    let win = guiWindow("Dock Tutorial", 900, 600)

    // Create the widgets — initial geometry doesn't matter; the dock
    // will reposition them in guiDockApply.
    let tree   = guiTreeView(win, 0, 0, 1, 1)
    let log    = guiTextArea(win, 0, 0, 1, 1)
    let editor = guiTextArea(win, 0, 0, 1, 1)

    let r = guiTreeAdd(tree, "0", "src")
    guiTreeAdd(tree, r, "main.k")
    guiTreeAdd(tree, r, "lib.k")

    guiSetText(log,    "log panel — pinned to bottom\r\n")
    guiSetText(editor, "editor — fills the middle")

    let dock = guiDock(win)
    guiDockBottom(dock, log,    160)   // 160px tall along the bottom
    guiDockLeft(dock,   tree,   240)   // 240px wide along the left
    guiDockFill(dock,   editor)        // takes the rest
    guiDockApply(dock)

    let status = guiStatusBar(win)
    guiStatusParts(status, "*")
    guiStatusSet(status, 0, " Resize the window — the panels reflow.")

    guiShow(win)
    guiRun()
}
