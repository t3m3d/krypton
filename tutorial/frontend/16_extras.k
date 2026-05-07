// 16_extras.k — combo box, color picker, date picker, scrollbar.
//
// All four are stock Win32 controls / dialogs wrapped by stdlib/gui.k.
// Combo is a dropdown list, color picker is a system modal dialog,
// date picker is a calendar dropdown, scrollbar is a standalone bar
// you can use as a numeric range input.

import "stdlib/gui.k"


let g_combo  = ""
let g_date   = ""
let g_scroll = ""
let g_label  = ""


func onComboChange()  { guiSetText(g_label, "Combo: "  + guiComboSelected(g_combo)) }
func onDateChange()   { guiSetText(g_label, "Date: "   + guiDateGet(g_date)) }
func onScrollChange() { guiSetText(g_label, "Scroll: " + guiScrollbarValue(g_scroll)) }

func onPickColor() {
    let c = guiColorPicker("0xFFA657")
    if len(c) > 0 { guiSetText(g_label, "Color: " + c) }
}


just run {
    guiInit()
    let win = guiWindow("Extras Tutorial", 480, 360)

    guiLabel(win, "Fruit:", 24, 24, 432, 22)
    g_combo = guiCombo(win, 24, 50, 432, 200)
    guiComboAdd(g_combo, "Apple")
    guiComboAdd(g_combo, "Banana")
    guiComboAdd(g_combo, "Cherry")
    guiComboSet(g_combo, 0)
    guiOnChange(g_combo, funcptr(onComboChange))

    guiLabel(win, "Date:", 24, 92, 432, 22)
    g_date = guiDatePicker(win, 24, 118, 432, 28)
    guiOnChange(g_date, funcptr(onDateChange))

    guiLabel(win, "Scroll (0-100):", 24, 160, 432, 22)
    g_scroll = guiScrollbar(win, 24, 186, 432, 22, 0)
    guiScrollbarRange(g_scroll, 0, 100, 10)
    guiScrollbarSet(g_scroll, 30)
    guiOnChange(g_scroll, funcptr(onScrollChange))

    let bC = guiButton(win, "Pick color...", 24, 224, 432, 32)
    guiOnClick(bC, funcptr(onPickColor))

    g_label = guiLabel(win, "Try the controls.", 24, 270, 432, 22)

    guiShow(win)
    guiRun()
}
