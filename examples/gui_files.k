// gui_files.k - file dialog demo (open / save / pick folder).
//
// Build:
//   kcc.exe examples/gui_files.k > tmp.c
//   gcc tmp.c -o gui_files.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// Three buttons each opening a different system dialog. The selected
// path is shown in a label. guiOpenFile / guiSaveFile take a filter
// CSV like "Krypton (*.k)|*.k,All Files|*.*" — pipe separates label
// from pattern, comma separates entries.

import "stdlib/gui.k"


let g_label = ""


func onOpen() {
    let path = guiOpenFile("Pick a Krypton source", "Krypton (*.k)|*.k,All Files|*.*")
    if len(path) == 0 { guiSetText(g_label, "(open cancelled)") }
    else              { guiSetText(g_label, "Opened: " + path) }
}

func onSave() {
    let path = guiSaveFile("Save where?", "Text Files|*.txt,All Files|*.*", "untitled.txt")
    if len(path) == 0 { guiSetText(g_label, "(save cancelled)") }
    else              { guiSetText(g_label, "Saving: " + path) }
}

func onPick() {
    let dir = guiPickFolder("Pick a folder")
    if len(dir) == 0 { guiSetText(g_label, "(folder cancelled)") }
    else             { guiSetText(g_label, "Folder: " + dir) }
}


just run {
    guiInit()
    let win = guiWindow("File Dialog Demo", 560, 240)

    let bO = guiButton(win, "Open File...",   24, 28, 168, 36)
    let bS = guiButton(win, "Save File...",  204, 28, 168, 36)
    let bD = guiButton(win, "Pick Folder...",384, 28, 152, 36)
    guiOnClick(bO, funcptr(onOpen))
    guiOnClick(bS, funcptr(onSave))
    guiOnClick(bD, funcptr(onPick))

    g_label = guiLabel(win, "Click a button.", 24, 84, 512, 80)

    guiShow(win)
    guiRun()
}
