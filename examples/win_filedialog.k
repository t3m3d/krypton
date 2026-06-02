// win_filedialog.k — open file picker + show the chosen path.
//
// Build:
//   kcc examples/win_filedialog.k -o win_filedialog.exe
//
// guiOpenFile pops the standard Windows file dialog and returns the
// selected path as a string (or "" if the user cancelled). The label
// updates to either the path or "(cancelled)".

import "k:gui"

func onPick() {
    let path = guiOpenFile("Pick a file", "All files,*.*,Text files,*.txt")
    let lbl  = guiStateGet("fd.label")
    if len(path) == 0 {
        guiSetText(lbl, "(cancelled)")
    } else {
        guiSetText(lbl, path)
    }
}

just run {
    guiInit()
    let win = guiWindow("Krypton File Dialog", 520, 200)

    let btn = guiButton(win, "Open file…", 20, 24, 140, 32)
    let lbl = guiLabel(win, "(no file selected)", 20, 80, 470, 28)

    guiStateSet("fd.label", lbl)
    guiOnClick(btn, funcptr(onPick))

    guiShow(win)
    guiRun()
}
