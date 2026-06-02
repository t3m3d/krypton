// win_notepad.k — minimal text editor with File / Edit menus.
//
// Build:
//   kcc examples/win_notepad.k -o win_notepad.exe
//
// Demonstrates the canonical "load text into a multi-line edit + menu
// commands" pattern. File → Open reads a file via guiOpenFile + readFile
// and pushes the contents into the text area; File → Save writes them
// back. Edit menu items pop a placeholder message box (real clipboard
// integration is a separate gui.k surface still being wired).

import "k:gui"

func _editor() { emit guiStateGet("np.editor") }

func onOpen() {
    let path = guiOpenFile("Open file", "Text files,*.txt;*.k;*.ks,All files,*.*")
    if len(path) == 0 { emit "" }
    let body = readFile(path)
    guiSetText(_editor(), body)
    guiStateSet("np.path", path)
}

func onSave() {
    let path = guiStateGet("np.path")
    if len(path) == 0 {
        path = guiSaveFile("Save as", "Text files,*.txt,All files,*.*", "untitled.txt")
        if len(path) == 0 { emit "" }
        guiStateSet("np.path", path)
    }
    writeFile(path, guiGetText(_editor()))
}

func onCut()   { guiMessageBox("Notepad", "Cut not wired yet") }
func onCopy()  { guiMessageBox("Notepad", "Copy not wired yet") }
func onPaste() { guiMessageBox("Notepad", "Paste not wired yet") }
func onQuit()  { guiQuit() }

just run {
    guiInit()
    let win = guiWindow("Krypton Notepad", 640, 420)

    let editor = guiTextArea(win, 0, 0, 640, 380)
    guiStateSet("np.editor", editor)

    let bar = guiMenuBegin(win)

    let fileMenu = guiMenu(bar, "File")
    guiOnClick(guiMenuItem(fileMenu, "Open…"), funcptr(onOpen))
    guiOnClick(guiMenuItem(fileMenu, "Save"),  funcptr(onSave))
    guiMenuSeparator(fileMenu)
    guiOnClick(guiMenuItem(fileMenu, "Quit"),  funcptr(onQuit))

    let editMenu = guiMenu(bar, "Edit")
    guiOnClick(guiMenuItem(editMenu, "Cut"),   funcptr(onCut))
    guiOnClick(guiMenuItem(editMenu, "Copy"),  funcptr(onCopy))
    guiOnClick(guiMenuItem(editMenu, "Paste"), funcptr(onPaste))

    guiShow(win)
    guiRun()
}
