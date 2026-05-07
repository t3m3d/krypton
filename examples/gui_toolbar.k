// gui_toolbar.k — toolbar with bitmap buttons demo.
//
// Build (from krypton/):
//   kcc.exe examples/gui_toolbar.k > tmp.c
//   gcc tmp.c -o gui_toolbar.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 \
//       -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
//
// Toolbar pinned to the top edge with stock Windows icons. Resizes
// with the window. Each button fires a callback like a regular
// guiButton.
//
// Available icon names: new, open, save, cut, copy, paste, undo, redo,
// delete, print, find, replace, help, props. Pass "" for text-only.

import "stdlib/gui.k"


let g_status = ""


func say(label) { guiStatusSet(g_status, 0, " " + label) }

func onNew()    { say("File: New") }
func onOpen()   { say("File: Open") }
func onSave()   { say("File: Save") }
func onCut()    { say("Edit: Cut") }
func onCopy()   { say("Edit: Copy") }
func onPaste()  { say("Edit: Paste") }
func onUndo()   { say("Edit: Undo") }
func onPrint()  { say("File: Print") }
func onFind()   { say("Find") }
func onHelp()   { guiMessageBox("Help", "Krypton toolbar demo") }


just run {
    guiInit()
    let win = guiWindow("Toolbar Demo", 720, 360)

    let tb = guiToolbar(win)
    let bNew  = guiToolButton(tb, "New",   "new")
    let bOpen = guiToolButton(tb, "Open",  "open")
    let bSave = guiToolButton(tb, "Save",  "save")
    guiToolSep(tb)
    let bCut  = guiToolButton(tb, "Cut",   "cut")
    let bCopy = guiToolButton(tb, "Copy",  "copy")
    let bPaste= guiToolButton(tb, "Paste", "paste")
    guiToolSep(tb)
    let bUndo = guiToolButton(tb, "Undo",  "undo")
    let bPrint= guiToolButton(tb, "Print", "print")
    let bFind = guiToolButton(tb, "Find",  "find")
    let bHelp = guiToolButton(tb, "Help",  "help")

    guiOnClick(bNew,   funcptr(onNew))
    guiOnClick(bOpen,  funcptr(onOpen))
    guiOnClick(bSave,  funcptr(onSave))
    guiOnClick(bCut,   funcptr(onCut))
    guiOnClick(bCopy,  funcptr(onCopy))
    guiOnClick(bPaste, funcptr(onPaste))
    guiOnClick(bUndo,  funcptr(onUndo))
    guiOnClick(bPrint, funcptr(onPrint))
    guiOnClick(bFind,  funcptr(onFind))
    guiOnClick(bHelp,  funcptr(onHelp))

    let tbH = toInt(guiToolbarHeight(tb))
    guiLabel(win, "Click any toolbar button.",
             24, tbH + 16, 660, 22)

    g_status = guiStatusBar(win)
    guiStatusParts(g_status, "*")
    guiStatusSet(g_status, 0, " Ready")

    guiShow(win)
    guiRun()
}
