// gui_extras.k — combo box / color picker / date picker / scrollbar.
//
// Build:
//   kcc.exe examples/gui_extras.k > tmp.c
//   gcc tmp.c -o gui_extras.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w

import "stdlib/gui.k"


let g_combo  = ""
let g_date   = ""
let g_scroll = ""
let g_label  = ""


func onPickColor() {
    let c = guiColorPicker("0xFFA657")
    if len(c) > 0 {
        guiSetText(g_label, "Picked color: " + c)
        guiStatusBgColor(guiStatusBar, c)   // not wired — just shows the value
    }
}

func onComboChange() {
    guiSetText(g_label, "Combo: " + guiComboSelected(g_combo))
}

func onDateChange() {
    guiSetText(g_label, "Date: " + guiDateGet(g_date))
}

func onScrollChange() {
    guiSetText(g_label, "Scroll: " + guiScrollbarValue(g_scroll))
}


just run {
    guiInit()
    let win = guiWindow("Extra Widgets", 540, 380)

    let lay = guiVStack(win, 24, 24, 492, 12)

    guiVLabel(lay, "Combo box:", 22)
    g_combo = guiCombo(win, toInt(guiStackX(lay)), toInt(guiVNext(lay, 28)),
                      toInt(guiStackW(lay)), 200)
    guiComboAdd(g_combo, "Apple")
    guiComboAdd(g_combo, "Banana")
    guiComboAdd(g_combo, "Cherry")
    guiComboSet(g_combo, 0)
    guiOnChange(g_combo, funcptr(onComboChange))

    guiVGap(lay, 8)
    guiVLabel(lay, "Date picker:", 22)
    g_date = guiDatePicker(win, toInt(guiStackX(lay)), toInt(guiVNext(lay, 28)),
                          toInt(guiStackW(lay)), 28)
    guiOnChange(g_date, funcptr(onDateChange))

    guiVGap(lay, 8)
    guiVLabel(lay, "Scrollbar:", 22)
    g_scroll = guiScrollbar(win, toInt(guiStackX(lay)), toInt(guiVNext(lay, 22)),
                            toInt(guiStackW(lay)), 22, 0)
    guiScrollbarRange(g_scroll, 0, 100, 10)
    guiScrollbarSet(g_scroll, 25)
    guiOnChange(g_scroll, funcptr(onScrollChange))

    guiVGap(lay, 12)
    let bColor = guiVButton(lay, "Pick color...", 36)
    guiOnClick(bColor, funcptr(onPickColor))

    guiVGap(lay, 12)
    g_label = guiVLabel(lay, "Try the controls above.", 22)

    guiShow(win)
    guiRun()
}
