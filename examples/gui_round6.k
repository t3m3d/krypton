// gui_round6.k — smoke test for round 6 macOS additions: color picker
// + scrollbar. Drag the scrollbar; the label updates with the latest
// reading. Click the button to open the color picker.

import "stdlib/gui.k"


let g_label = ""
let g_sb    = ""


func onPick() {
    let c = guiColorPicker("0x3366CC")
    if len(c) == 0 {
        guiSetText(g_label, "Cancelled.")
    } else {
        guiSetText(g_label, "Picked: " + c)
    }
}

func onScroll() {
    let v = guiScrollbarValue(g_sb)
    guiSetText(g_label, "Scrollbar: " + v)
}


just run {
    guiInit()
    let win = guiWindow("Krypton Round-6 Smoke Test", 480, 240)

    let bPick = guiButton(win, "Pick a color", 24, 24, 200, 32)
    guiOnClick(bPick, funcptr(onPick))

    g_sb = guiScrollbar(win, 24, 80, 432, 16, 0)
    guiScrollbarRange(g_sb, 0, 200, 20)
    guiScrollbarSet(g_sb, 50)
    guiOnChange(g_sb, funcptr(onScroll))

    g_label = guiLabel(win, "Click the button or drag the scrollbar.",
                      24, 120, 432, 22)

    guiShow(win)
    guiRun()
}
