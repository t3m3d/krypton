// 08_treeview.k — file-tree-style hierarchy with modern triangles.
//
// guiTreeView returns a handle. guiTreeAdd(tree, parent_or_"0", label)
// inserts a node — pass "0" for top-level, or another item handle to
// nest. Selection changes fire guiOnChange.

import "stdlib/gui.k"


let g_tree  = ""
let g_label = ""


func onSelect() {
    let pick = guiTreeSelected(g_tree)
    if len(pick) == 0 { pick = "(none)" }
    guiSetText(g_label, "Selected: " + pick)
}


just run {
    guiInit()
    let win = guiWindow("TreeView Demo", 440, 420)

    g_tree = guiTreeView(win, 12, 12, 416, 340)

    let r1 = guiTreeAdd(g_tree, "0", "src")
    guiTreeAdd(g_tree, r1, "main.k")
    guiTreeAdd(g_tree, r1, "lib.k")

    let r2 = guiTreeAdd(g_tree, "0", "tests")
    guiTreeAdd(g_tree, r2, "test_basic.k")
    guiTreeAdd(g_tree, r2, "test_edge.k")

    guiOnChange(g_tree, funcptr(onSelect))

    g_label = guiLabel(win, "Click a node above.", 12, 360, 416, 22)

    guiShow(win)
    guiRun()
}
