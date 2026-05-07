// gui_treeview.k - TreeView + Tab control demo.
//
// Build:
//   kcc.exe examples/gui_treeview.k > tmp.c
//   gcc tmp.c -o gui_treeview.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi \
//       -luxtheme -ladvapi32 -lm -w
//
// One window, two tabs (Tree, Notes). Click parent rows in the tree
// to expand/collapse with modern triangle indicators.
//
// All strings are pure ASCII because Win32 ANSI APIs (the A-suffix
// ones we use) treat the bytes as windows-1252, not UTF-8. Non-ASCII
// glyphs render as mojibake. A future tier of stdlib/gui.k can switch
// to the W APIs + UTF-8 conversion to fix this properly.

import "stdlib/gui.k"


let g_tree   = ""
let g_label  = ""
let g_tabs   = ""
let g_notes  = ""


func onTreeSelect() {
    let pick = guiTreeSelected(g_tree)
    if len(pick) == 0 { pick = "(none)" }
    guiSetText(g_label, "Selected: " + pick)
}

func onTabChange() {
    let idx = guiTabSelected(g_tabs)
    if idx == "0" {
        guiSetText(g_label, "Tree tab")
    } else {
        guiSetText(g_label, "Notes tab")
    }
}


just run {
    guiInit()
    let win = guiWindow("Krypton: Tree + Tabs", 640, 480)

    g_tabs = guiTabs(win, 12, 12, 616, 28)
    guiTabAdd(g_tabs, "Tree")
    guiTabAdd(g_tabs, "Notes")
    guiOnChange(g_tabs, funcptr(onTabChange))

    // Tree on tab 0. Items start collapsed; click the triangle next
    // to a parent row to expand.
    g_tree = guiTreeView(win, 12, 56, 300, 360)
    let r1 = guiTreeAdd(g_tree, "0", "src")
    guiTreeAdd(g_tree, r1, "main.k")
    guiTreeAdd(g_tree, r1, "lib.k")
    let r2 = guiTreeAdd(g_tree, "0", "tests")
    guiTreeAdd(g_tree, r2, "test_basic.k")
    guiTreeAdd(g_tree, r2, "test_edge.k")
    let r3 = guiTreeAdd(g_tree, "0", "docs")
    guiTreeAdd(g_tree, r3, "spec.md")
    guiTreeAdd(g_tree, r3, "tutorial.md")
    guiOnChange(g_tree, funcptr(onTreeSelect))

    // Notes on tab 1.
    g_notes = guiTextArea(win, 320, 56, 308, 360)
    guiSetText(g_notes, "Notes pane. Type something here, click the Tree tab to switch.")

    g_label = guiLabel(win, "Click a node above.", 12, 426, 616, 22)

    guiShow(win)
    guiRun()
}
