// win_toolbar.k — toolbar + status bar + click handlers.
//
// Build:
//   kcc examples/win_toolbar.k -o win_toolbar.exe
//
// A top toolbar with three buttons (New / Open / Save) plus a status
// bar at the bottom. Clicking a button updates the status bar so you
// see the dispatch. Same pattern any real desktop app uses.

import "k:gui"

func _bar() { emit guiStateGet("tb.status") }

func onNew()  { guiStatusSet(_bar(), 0, "New document") }
func onOpen() { guiStatusSet(_bar(), 0, "Open clicked") }
func onSave() { guiStatusSet(_bar(), 0, "Saved") }

just run {
    guiInit()
    let win = guiWindow("Krypton Toolbar", 540, 360)

    let tb = guiToolbar(win)
    let bNew  = guiToolButton(tb, "New",  "new")
    let bOpen = guiToolButton(tb, "Open", "open")
    guiToolSep(tb)
    let bSave = guiToolButton(tb, "Save", "save")

    let bar = guiStatusBar(win)
    guiStatusSet(bar, 0, "Ready")
    guiStateSet("tb.status", bar)

    guiOnClick(bNew,  funcptr(onNew))
    guiOnClick(bOpen, funcptr(onOpen))
    guiOnClick(bSave, funcptr(onSave))

    guiShow(win)
    guiRun()
}
