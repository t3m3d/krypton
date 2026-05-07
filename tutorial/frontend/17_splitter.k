// 17_splitter.k — drag-to-resize bar between two panels.
//
// guiSplitter creates a thin gray bar; user drags it to fire onChange.
// Your callback reads guiSplitterPos and uses guiMove to reposition
// the panels around the new bar position.
//
// Orientation:
//   "vertical"   thin tall bar — drag left/right
//   "horizontal" wide thin bar — drag up/down

import "stdlib/gui.k"


let g_left  = ""
let g_right = ""
let g_split = ""

let WIN_W   = 720
let WIN_H   = 460
let MARGIN  = 12
let SPLIT_W = 6
let TOP     = 12
let BOTTOM  = 380


func onSplit() {
    let x = toInt(guiSplitterPos(g_split))
    if x < 80         { x = 80 }
    if x > WIN_W - 100 { x = WIN_W - 100 }
    guiMove(g_left,  MARGIN, TOP, x - MARGIN - 2, BOTTOM)
    guiMove(g_split, x,      TOP, SPLIT_W,        BOTTOM)
    guiMove(g_right, x + SPLIT_W + 2, TOP,
            WIN_W - x - SPLIT_W - 2 - MARGIN, BOTTOM)
}


just run {
    guiInit()
    let win = guiWindow("Splitter Tutorial", WIN_W, WIN_H)

    g_left = guiListbox(win, MARGIN, TOP, 240, BOTTOM)
    guiListAdd(g_left, "main.k")
    guiListAdd(g_left, "lib.k")
    guiListAdd(g_left, "tests.k")

    g_split = guiSplitter(win, 256, TOP, SPLIT_W, BOTTOM, "vertical")
    guiOnChange(g_split, funcptr(onSplit))

    g_right = guiListbox(win, 268, TOP, 432, BOTTOM)
    guiListAdd(g_right, "result one")
    guiListAdd(g_right, "result two")

    guiLabel(win, "Drag the gray bar.", MARGIN, 404, WIN_W - 2 * MARGIN, 22)

    guiShow(win)
    guiRun()
}
