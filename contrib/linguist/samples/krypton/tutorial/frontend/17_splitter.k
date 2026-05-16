// 17_splitter.k — drag-to-resize bar between two panels.
//
// guiSplitter creates a thin gray bar; user drags it to fire onChange.
// Your callback reads guiSplitterPos and uses guiMove to reposition
// the panels around the new bar position.
//
// Orientation:
//   "vertical"   thin tall bar — drag left/right
//   "horizontal" wide thin bar — drag up/down
//
// Note: cross-handler state goes through `guiStateSet`/`guiStateGet`
// rather than module-level `let` (which is broken in the native
// pipeline — see Krypton's own --port-1to2 warning).

import "k:gui"


let WIN_W   = 720
let WIN_H   = 460
let MARGIN  = 12
let SPLIT_W = 6
let TOP     = 12
let BOTTOM  = 380


func onSplit() {
    let left  = guiStateGet("demo.left")
    let right = guiStateGet("demo.right")
    let split = guiStateGet("demo.split")
    let x = toInt(guiSplitterPos(split))
    if x < 80         { x = 80 }
    if x > WIN_W - 100 { x = WIN_W - 100 }
    guiMove(left,  MARGIN, TOP, x - MARGIN - 2, BOTTOM)
    guiMove(split, x,      TOP, SPLIT_W,        BOTTOM)
    guiMove(right, x + SPLIT_W + 2, TOP,
            WIN_W - x - SPLIT_W - 2 - MARGIN, BOTTOM)
}


just run {
    guiInit()
    let win = guiWindow("Splitter Tutorial", WIN_W, WIN_H)

    let left = guiListbox(win, MARGIN, TOP, 240, BOTTOM)
    guiListAdd(left, "main.k")
    guiListAdd(left, "lib.k")
    guiListAdd(left, "tests.k")
    guiStateSet("demo.left", left)

    let split = guiSplitter(win, 256, TOP, SPLIT_W, BOTTOM, "vertical")
    guiOnChange(split, funcptr(onSplit))
    guiStateSet("demo.split", split)

    let right = guiListbox(win, 268, TOP, 432, BOTTOM)
    guiListAdd(right, "result one")
    guiListAdd(right, "result two")
    guiStateSet("demo.right", right)

    guiLabel(win, "Drag the gray bar.", MARGIN, 404, WIN_W - 2 * MARGIN, 22)

    guiShow(win)
    guiRun()
}
