// 19_layout_stacks.k — guiVStack / guiHStack auto-layout helpers.
//
// Stop computing y manually. guiVStack pins x + width + gap; every
// guiV* helper drops the next widget at the right place. V-stacks
// also auto-grow their cross axis (width) when the window resizes.
//
// guiHStack is the horizontal counterpart — pin y + height, walk
// widgets across.

import "stdlib/gui.k"


let g_first = ""
let g_last  = ""
let g_pref  = ""


func onSubmit() {
    let extra = ""
    if guiIsChecked(g_pref) == "1" { extra = " (preferred)" }
    guiMessageBox("Submitted",
        guiGetText(g_first) + " " + guiGetText(g_last) + extra)
}


just run {
    guiInit()
    let win = guiWindow("Layout Stacks", 480, 460)

    let lay = guiVStack(win, 24, 24, 432, 10)

    guiVLabel(lay, "First name:", 22)
    g_first = guiVInput(lay, 30)

    guiVLabel(lay, "Last name:", 22)
    g_last = guiVInput(lay, 30)

    guiVGap(lay, 10)
    g_pref = guiVCheckbox(lay, "Mark as preferred", 24)

    guiVGap(lay, 10)
    let bSub = guiVButton(lay, "Submit", 36)
    guiOnClick(bSub, funcptr(onSubmit))

    guiVGap(lay, 10)
    guiVLabel(lay, "Notes:", 22)
    guiVTextArea(lay, 120)

    guiShow(win)
    guiRun()
}
