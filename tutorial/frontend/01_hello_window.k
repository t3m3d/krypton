// 01_hello_window.k — the smallest GUI program.
//
// Three calls is all it takes:
//   guiInit() — once at startup
//   guiWindow(...) — make a window
//   guiShow(...) + guiRun() — display it and run the event loop

import "stdlib/gui.k"

just run {
    guiInit()
    let win = guiWindow("Hello, Krypton GUI", 400, 240)
    guiShow(win)
    guiRun()
}
