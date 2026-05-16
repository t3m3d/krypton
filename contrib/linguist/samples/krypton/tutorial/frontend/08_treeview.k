// 08_treeview.k — file-tree-style hierarchy with modern triangles.
//
// guiTreeView returns a handle. guiTreeAdd(tree, parent_or_"0", label)
// inserts a node — pass "0" for top-level, or another item handle to
// nest. Selection changes fire guiOnChange.
//
// Note: cross-handler state goes through `guiStateSet`/`guiStateGet`
// rather than module-level `let` (which is broken in the native
// pipeline — see Krypton's own --port-1to2 warning).

import "k:gui"


func onSelect() {
    let tree = guiStateGet("demo.tree")
    let label = guiStateGet("demo.label")
    let pick = guiTreeSelected(tree)
    if len(pick) == 0 { pick = "(none)" }
    guiSetText(label, "Selected: " + pick)
}


just run {
    guiInit()
    let win = guiWindow("TreeView Demo", 440, 420)

    let tree = guiTreeView(win, 12, 12, 416, 340)
    guiStateSet("demo.tree", tree)

    let r1 = guiTreeAdd(tree, "0", "src")
    guiTreeAdd(tree, r1, "main.k")
    guiTreeAdd(tree, r1, "lib.k")

    let r2 = guiTreeAdd(tree, "0", "tests")
    guiTreeAdd(tree, r2, "test_basic.k")
    guiTreeAdd(tree, r2, "test_edge.k")

    guiOnChange(tree, funcptr(onSelect))

    let label = guiLabel(win, "Click a node above.", 12, 360, 416, 22)
    guiStateSet("demo.label", label)

    guiShow(win)
    guiRun()
}
