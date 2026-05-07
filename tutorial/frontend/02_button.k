// 02_button.k — a clickable button.
//
// guiButton returns a handle. Wire a callback with guiOnClick passing
// funcptr(name). The callback is a normal no-arg func.

import "stdlib/gui.k"


func onClick() {
    guiMessageBox("Hi!", "You clicked the button.")
}


just run {
    guiInit()
    let win = guiWindow("Button Demo", 400, 200)

    let btn = guiButton(win, "Click me", 24, 60, 350, 40)
    guiOnClick(btn, funcptr(onClick))

    guiShow(win)
    guiRun()
}
