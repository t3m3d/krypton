// gui_dock.k — VS-style dock layout: tree on left, log on bottom,
// editor area filling the middle. Auto-resizes with the window.
//
// Build:
//   kcc.exe examples/gui_dock.k > tmp.c
//   gcc tmp.c -o gui_dock.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w

import "stdlib/gui.k"


just run {
    guiInit()
    let win = guiWindow("Dock Layout Demo", 900, 600)

    // Create the widgets — dock manager ignores their initial geometry.
    let tree   = guiTreeView(win,  0, 0, 1, 1)
    let log    = guiTextArea(win,  0, 0, 1, 1)
    let editor = guiTextArea(win,  0, 0, 1, 1)
    let status = guiStatusBar(win)
    guiStatusParts(status, "*,*")
    guiStatusSet(status, 0, " Ready")
    guiStatusSet(status, 1, " UTF-8")

    // Populate the tree.
    let r1 = guiTreeAdd(tree, "0", "src")
    guiTreeAdd(tree, r1, "main.k")
    guiTreeAdd(tree, r1, "lib.k")
    let r2 = guiTreeAdd(tree, "0", "tests")
    guiTreeAdd(tree, r2, "test_basic.k")

    guiSetText(log,    "[log] dock demo started\r\n")
    guiSetText(editor, "// editor area — fills whatever space the\r\n// other panels don't claim.")

    // Dock layout: top→bottom, left→right ordering. Status bar handles
    // its own bottom anchoring via WM_SIZE so don't add it here.
    let dock = guiDock(win)
    guiDockBottom(dock, log,    160)
    guiDockLeft(dock,   tree,   240)
    guiDockFill(dock,   editor)
    guiDockApply(dock)

    guiShow(win)
    guiRun()
}
