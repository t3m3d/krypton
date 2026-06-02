// win_listview.k — list of items + status bar showing the current selection.
//
// Build:
//   kcc examples/win_listview.k -o win_listview.exe
//
// stdlib/gui.k exposes a single-column listbox (the multi-column native
// ListView control isn't surfaced yet — coming whenever the underlying
// Win32 LVS_REPORT bindings get a higher-level wrapper). For this demo
// a single-column listbox is enough to show the pattern: build a list,
// react to selection changes, update the status bar.

import "k:gui"

func _list()   { emit guiStateGet("lv.list") }
func _status() { emit guiStateGet("lv.status") }

func onSelectionChanged() {
    let idx = guiListSelected(_list())
    if idx < 0 {
        guiStatusSet(_status(), 0, "Nothing selected")
    } else {
        guiStatusSet(_status(), 0, "Selected row " + idx)
    }
}

just run {
    guiInit()
    let win = guiWindow("Krypton ListView (single-column)", 540, 360)

    let list = guiListbox(win, 12, 12, 516, 280)
    let bar  = guiStatusBar(win)

    guiListAdd(list, "Apple        — fruit")
    guiListAdd(list, "Banana       — fruit")
    guiListAdd(list, "Carrot       — vegetable")
    guiListAdd(list, "Date         — fruit")
    guiListAdd(list, "Eggplant     — vegetable")
    guiListAdd(list, "Fig          — fruit")
    guiListAdd(list, "Garlic       — vegetable")

    guiStatusSet(bar, 0, "Click a row")
    guiStateSet("lv.list", list)
    guiStateSet("lv.status", bar)
    guiOnChange(list, funcptr(onSelectionChanged))

    guiShow(win)
    guiRun()
}
