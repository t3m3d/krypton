// win_textinput.k — single-line text input + button + live echo label.
//
// Build:
//   kcc examples/win_textinput.k -o win_textinput.exe
//
// Type something in the field, click "Greet", and the label updates to
// "Hello, <name>!". guiGetText reads the current contents of the edit
// control; guiSetText pushes a new value into the label.

import "k:gui"

func onGreet() {
    let name = guiGetText(guiStateGet("ti.input"))
    if len(name) == 0 { name = "stranger" }
    guiSetText(guiStateGet("ti.label"), "Hello, " + name + "!")
}

just run {
    guiInit()
    let win = guiWindow("Krypton Text Input", 420, 200)

    guiLabel(win, "Your name:", 20, 24, 100, 24)
    let input = guiTextInput(win, 130, 22, 260, 28)
    let lbl   = guiLabel(win, "Hello, stranger!", 20, 70, 370, 28)
    let btn   = guiButton(win, "Greet", 20, 110, 100, 32)

    guiStateSet("ti.input", input)
    guiStateSet("ti.label", lbl)
    guiOnClick(btn, funcptr(onGreet))

    guiShow(win)
    guiRun()
}
