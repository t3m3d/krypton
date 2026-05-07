// gui_splitter.k - vertical splitter between two listboxes.
//
// Build:
//   kcc.exe examples/gui_splitter.k > tmp.c
//   gcc tmp.c -o gui_splitter.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// The splitter only moves itself. Your onChange callback uses
// guiSplitterPos + guiMove to reposition the panels around it.

import "stdlib/gui.k"


let g_left  = ""
let g_right = ""
let g_split = ""

let WIN_W = 720
let WIN_H = 460
let MARGIN  = 12
let SPLIT_W = 6
let TOP     = 12
let BOTTOM  = 380


func onSplit() {
    let xs = guiSplitterPos(g_split)
    let x = toInt(xs)
    if x < 80               { x = 80 }
    if x > WIN_W - 100      { x = WIN_W - 100 }
    // Re-layout the panels around the new splitter position.
    guiMove(g_left,  MARGIN, TOP, x - MARGIN - 2,                BOTTOM)
    guiMove(g_split, x,      TOP, SPLIT_W,                       BOTTOM)
    guiMove(g_right, x + SPLIT_W + 2, TOP,
            WIN_W - x - SPLIT_W - 2 - MARGIN,                    BOTTOM)
}


just run {
    guiInit()
    let win = guiWindow("Splitter Demo", WIN_W, WIN_H)

    g_left  = guiListbox(win, MARGIN, TOP, 240, BOTTOM)
    guiListAdd(g_left, "main.k")
    guiListAdd(g_left, "lib.k")
    guiListAdd(g_left, "tests.k")
    guiListAdd(g_left, "README.md")

    g_split = guiSplitter(win, 256, TOP, SPLIT_W, BOTTOM, "vertical")
    guiOnChange(g_split, funcptr(onSplit))

    g_right = guiListbox(win, 268, TOP, 432, BOTTOM)
    guiListAdd(g_right, "result one")
    guiListAdd(g_right, "result two")
    guiListAdd(g_right, "result three")

    guiLabel(win, "Drag the gray vertical bar to resize.",
             MARGIN, 404, WIN_W - 2 * MARGIN, 22)

    guiShow(win)
    guiRun()
}
