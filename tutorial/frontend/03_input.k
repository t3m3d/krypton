// 03_input.k — read text from a text input.
//
// guiTextInput returns a handle. Read its current text with
// guiGetText(handle). Storing the handle in a module-level global lets
// the click callback see it.

import "stdlib/gui.k"


let g_input = ""


func onGreet() {
    let name = guiGetText(g_input)
    if len(name) == 0 {
        guiMessageBox("Wait", "Type your name first.")
    } else {
        guiMessageBox("Hello", "Nice to meet you, " + name + "!")
    }
}


just run {
    guiInit()
    let win = guiWindow("Input Demo", 420, 200)

    guiLabel(win, "Your name:", 24, 18, 380, 22)
    g_input = guiTextInput(win,  24, 44, 380, 30)

    let btn = guiButton(win, "Greet me", 24, 90, 380, 36)
    guiOnClick(btn, funcptr(onGreet))

    guiShow(win)
    guiRun()
}
