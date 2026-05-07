// gui_hello.k — minimal GUI demo using stdlib/gui.k.
//
// Build (from krypton/):
//   kcc.exe examples/gui_hello.k > tmp.c
//   gcc tmp.c -o gui_hello.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi \
//       -luxtheme -ladvapi32 -lm -w
//   .\gui_hello.exe
//
// Showcases stdlib/gui.k:
//   - guiWindow with auto dark titlebar following OS theme
//   - Common Controls v6 (rounded modern buttons via runtime manifest)
//   - Segoe UI 10pt on every control
//   - Click callback that reads input and pops a MessageBox

import "stdlib/gui.k"


// Module-level so the button callback can read it.
let g_input = ""


func onGreet() {
    let name = guiGetText(g_input)
    if len(name) == 0 {
        guiMessageBox("Krypton", "Type your name first!")
    } else {
        guiMessageBox("Krypton", "Hello, " + name + "!")
    }
}


just run {
    guiInit()
    let win = guiWindow("Krypton GUI Demo", 480, 260)

    // 24px outer margins, 12px between widget rows. Mirrors the
    // spacing Python+Tk apps use to avoid feeling cramped.
    guiLabel(win, "Your name:",                 24, 24, 432, 22)
    g_input = guiTextInput(win,                 24, 52, 432, 30)

    let btn = guiButton(win, "Greet me",        24, 100, 432, 38)
    guiOnClick(btn, funcptr(onGreet))

    guiLabel(win, "Krypton stdlib/gui.k demo",  24, 156, 432, 20)

    guiShow(win)
    guiRun()
}
