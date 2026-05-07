// 04_layout.k — composing multiple widgets cleanly.
//
// All widgets take x, y, w, h relative to the parent's client area.
// Pick a consistent left margin (say 24) and consistent vertical gap
// (say 12) and the layout looks tidy.
//
// In a future tier, guiVStack / guiHStack will handle this for you.

import "stdlib/gui.k"


let g_first  = ""
let g_last   = ""


func onCombine() {
    let f = guiGetText(g_first)
    let l = guiGetText(g_last)
    guiMessageBox("Combined", f + " " + l)
}


just run {
    guiInit()
    let win = guiWindow("Layout Demo", 460, 280)

    let lx = 24
    let lw = 412

    guiLabel(win, "First name:", lx, 24, lw, 22)
    g_first = guiTextInput(win,  lx, 50, lw, 30)

    guiLabel(win, "Last name:",  lx, 92, lw, 22)
    g_last  = guiTextInput(win,  lx, 118, lw, 30)

    let btn = guiButton(win, "Combine", lx, 168, lw, 36)
    guiOnClick(btn, funcptr(onCombine))

    guiShow(win)
    guiRun()
}
