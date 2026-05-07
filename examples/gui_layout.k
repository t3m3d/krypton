// gui_layout.k — vertical/horizontal stack helpers.
//
// Build:
//   kcc.exe examples/gui_layout.k > tmp.c
//   gcc tmp.c -o gui_layout.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// No more manual y-coord juggling. guiVStack pins x + width + gap,
// then every guiVLabel/guiVInput/guiVButton call drops the next
// widget at the right place.

import "stdlib/gui.k"


let g_first = ""
let g_last  = ""
let g_pref  = ""


func onSubmit() {
    let f = guiGetText(g_first)
    let l = guiGetText(g_last)
    let pref = ""
    if guiIsChecked(g_pref) == "1" { pref = " (preferred)" }
    guiMessageBox("Submitted", f + " " + l + pref)
}


just run {
    guiInit()
    let win = guiWindow("Layout Demo", 480, 420)

    // V-stack: x=24, y=24, width=432, gap=10 between widgets.
    let lay = guiVStack(win, 24, 24, 432, 10)

    guiVLabel(lay, "First name:", 22)
    g_first = guiVInput(lay, 30)

    guiVLabel(lay, "Last name:", 22)
    g_last  = guiVInput(lay, 30)

    guiVGap(lay, 10)
    g_pref = guiVCheckbox(lay, "Mark as preferred contact", 24)

    guiVGap(lay, 10)
    let bSubmit = guiVButton(lay, "Submit", 36)
    guiOnClick(bSubmit, funcptr(onSubmit))

    guiVGap(lay, 10)
    guiVLabel(lay, "Notes:", 22)
    guiVTextArea(lay, 100)

    guiShow(win)
    guiRun()
}
