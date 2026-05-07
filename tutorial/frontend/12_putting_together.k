// 12_putting_together.k — small Krypton GUI app combining everything.
//
// A toy "task list" with: menu bar, text input, list, checkbox,
// progress, status bar. Keep it under ~80 lines.

import "stdlib/gui.k"


let g_input = ""
let g_list  = ""
let g_done  = ""
let g_prog  = ""
let g_bar   = ""
let g_added = 0


func updateStatus() {
    guiStatusSet(g_bar, 0, " " + g_added + " items")
    let pct = 0
    if g_added > 0 { pct = (g_added * 10) }
    if pct > 100 { pct = 100 }
    guiProgressSet(g_prog, pct)
}

func onAdd() {
    let s = guiGetText(g_input)
    if len(s) == 0 { return }
    let prefix = "[ ] "
    if guiIsChecked(g_done) == "1" { prefix = "[x] " }
    guiListAdd(g_list, prefix + s)
    guiSetText(g_input, "")
    g_added = g_added + 1
    updateStatus()
    guiStatusIcon(g_bar, 0, "info")
}

func onPick() {
    let pick = guiListSelected(g_list)
    if len(pick) == 0 {
        guiStatusIcon(g_bar, 0, "warning")
        guiStatusSet(g_bar, 1, " Select an item")
    } else {
        guiStatusIcon(g_bar, 0, "ok")
        guiStatusSet(g_bar, 1, " Picked: " + pick)
    }
}

func onClear() {
    guiListClear(g_list)
    g_added = 0
    updateStatus()
    guiStatusIcon(g_bar, 0, "info")
    guiStatusSet(g_bar, 1, " cleared")
}

func onAbout() { guiMessageBox("About", "Krypton GUI tutorial — task list demo") }
func onQuit()  { guiQuit() }


just run {
    guiInit()
    let win = guiWindow("Tasks", 600, 480)

    let menu = guiMenuBegin(win)
    let mAbout = guiMenuAdd(menu, "Help: About")
    let mQuit  = guiMenuAdd(menu, "File: Quit")
    guiOnClick(mAbout, funcptr(onAbout))
    guiOnClick(mQuit,  funcptr(onQuit))

    guiLabel(win, "New task:", 24, 24, 552, 22)
    g_input = guiTextInput(win, 24, 50, 552, 30)

    g_done = guiCheckbox(win, "mark as done when added", 24, 90, 380, 24)

    let bAdd  = guiButton(win, "Add",     24, 124, 180, 32)
    let bPick = guiButton(win, "Pick",   216, 124, 180, 32)
    let bClr  = guiButton(win, "Clear",  408, 124, 168, 32)
    guiOnClick(bAdd,  funcptr(onAdd))
    guiOnClick(bPick, funcptr(onPick))
    guiOnClick(bClr,  funcptr(onClear))

    g_list = guiListbox(win, 24, 168, 552, 200)

    guiLabel(win, "Progress:", 24, 380, 100, 20)
    g_prog = guiProgress(win, 130, 382, 446, 18)

    g_bar = guiStatusBar(win)
    guiStatusParts(g_bar, "*,*")
    guiStatusSet(g_bar, 0, " 0 items")
    guiStatusIcon(g_bar, 0, "info")
    guiStatusSet(g_bar, 1, " ready")

    guiShow(win)
    guiRun()
}
