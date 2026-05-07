// 06_checkbox.k — boolean toggles.
//
// guiCheckbox returns a handle. guiIsChecked returns "1" / "0".
// guiSetChecked(handle, 1) checks programmatically.

import "stdlib/gui.k"


let g_check = ""


func onCheckState() {
    let v = guiIsChecked(g_check)
    if v == "1" {
        guiMessageBox("State", "Checkbox is ON.")
    } else {
        guiMessageBox("State", "Checkbox is OFF.")
    }
}

func onToggleProgrammatic() {
    let v = guiIsChecked(g_check)
    if v == "1" { guiSetChecked(g_check, 0) }
    else        { guiSetChecked(g_check, 1) }
}


just run {
    guiInit()
    let win = guiWindow("Checkbox Demo", 420, 240)

    g_check = guiCheckbox(win, "Enable feature X", 24, 24, 380, 28)
    guiSetChecked(g_check, 1)        // start checked

    let b1 = guiButton(win, "Read state", 24, 70, 380, 36)
    let b2 = guiButton(win, "Toggle me",  24, 114, 380, 36)
    guiOnClick(b1, funcptr(onCheckState))
    guiOnClick(b2, funcptr(onToggleProgrammatic))

    guiShow(win)
    guiRun()
}
