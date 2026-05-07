// 07_progress.k — progress bar with two buttons.
//
// guiProgressSet takes 0..100. We hold the current percent in a
// module-level global so both buttons can mutate it.

import "stdlib/gui.k"


let g_prog = ""
let g_pct  = 0


func onMore() {
    g_pct = g_pct + 10
    if g_pct > 100 { g_pct = 100 }
    guiProgressSet(g_prog, g_pct)
}

func onLess() {
    g_pct = g_pct - 10
    if g_pct < 0 { g_pct = 0 }
    guiProgressSet(g_prog, g_pct)
}


just run {
    guiInit()
    let win = guiWindow("Progress Demo", 460, 200)

    g_prog = guiProgress(win, 24, 30, 412, 22)

    let b1 = guiButton(win, "+10",  24, 70, 200, 36)
    let b2 = guiButton(win, "-10", 236, 70, 200, 36)
    guiOnClick(b1, funcptr(onMore))
    guiOnClick(b2, funcptr(onLess))

    guiShow(win)
    guiRun()
}
