// 13_toolbar.k — top toolbar with bitmap buttons.
//
// guiToolbar pins itself to the top edge and resizes with the window.
// Each guiToolButton takes a label and an icon name from the stock
// Windows image list. Pass "" for icon to get a text-only button.
//
// Available icons: new, open, save, cut, copy, paste, undo, redo,
// delete, print, find, replace, help, props.

import "stdlib/gui.k"


let g_label = ""


func say(msg) { guiSetText(g_label, msg) }

func onNew()  { say("File: New")  }
func onOpen() { say("File: Open") }
func onSave() { say("File: Save") }
func onCut()  { say("Edit: Cut")  }
func onCopy() { say("Edit: Copy") }
func onHelp() { guiMessageBox("Help", "Toolbar tutorial") }


just run {
    guiInit()
    let win = guiWindow("Toolbar Tutorial", 640, 280)

    let tb = guiToolbar(win)
    guiOnClick(guiToolButton(tb, "New",  "new"),  funcptr(onNew))
    guiOnClick(guiToolButton(tb, "Open", "open"), funcptr(onOpen))
    guiOnClick(guiToolButton(tb, "Save", "save"), funcptr(onSave))
    guiToolSep(tb)
    guiOnClick(guiToolButton(tb, "Cut",  "cut"),  funcptr(onCut))
    guiOnClick(guiToolButton(tb, "Copy", "copy"), funcptr(onCopy))
    guiToolSep(tb)
    guiOnClick(guiToolButton(tb, "Help", "help"), funcptr(onHelp))

    let tbH = toInt(guiToolbarHeight(tb))
    g_label = guiLabel(win, "Click any toolbar button.",
                      24, tbH + 16, 600, 22)

    guiShow(win)
    guiRun()
}
