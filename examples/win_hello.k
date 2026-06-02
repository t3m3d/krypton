// win_hello.k — the smallest Krypton GUI program.
//
// Build (native pipeline, no C compiler):
//   kcc examples/win_hello.k -o win_hello.exe
// Run:
//   .\win_hello.exe
//
// The whole Win32 IAT, the WindowProc, the message pump, the class
// registration — all of it lives behind `stdlib/gui.k` now. Three
// calls suffice for a real window.

import "k:gui"

just run {
    guiInit()
    let win = guiWindow("Krypton — Hello GUI", 520, 280)
    guiLabel(win, "Hello from Krypton!", 30, 30, 460, 28)
    guiLabel(win, "Window + message pump in pure Krypton.", 30, 60, 460, 28)
    guiShow(win)
    guiRun()
}
