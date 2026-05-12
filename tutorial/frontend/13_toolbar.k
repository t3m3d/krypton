// 13_toolbar.k — top toolbar with bitmap buttons.
//
// guiToolbar pins itself to the top edge and resizes with the window.
// Each guiToolButton takes a label and an icon name from the stock
// Windows image list. Pass "" for icon to get a text-only button.
//
// Available icons: new, open, save, cut, copy, paste, undo, redo,
// delete, print, find, replace, help, props.
//
// Note: cross-handler state goes through `guiStateSet`/`guiStateGet`
// rather than module-level `let` (which is broken in the native
// pipeline — see Krypton's own --port-1to2 warning).

import "k:gui"


func say(msg) { guiSetText(guiStateGet("demo.label"), msg) }

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
    let label = guiLabel(win, "Click any toolbar button.",
                      24, tbH + 16, 600, 22)
    guiStateSet("demo.label", label)

    guiShow(win)
    guiRun()
}
