// 05_listbox.k — dynamic list of items.
//
// guiListbox returns a handle. Add / clear / read selection via
// guiListAdd / guiListClear / guiListSelected.

import "stdlib/gui.k"


let g_input = ""
let g_list  = ""


func onAdd() {
    let s = guiGetText(g_input)
    if len(s) > 0 {
        guiListAdd(g_list, s)
        guiSetText(g_input, "")
    }
}

func onClear()  { guiListClear(g_list) }

func onShowSelected() {
    let pick = guiListSelected(g_list)
    if len(pick) == 0 {
        guiMessageBox("Listbox", "Select an item first.")
    } else {
        guiMessageBox("Listbox", "Selected: " + pick)
    }
}


just run {
    guiInit()
    let win = guiWindow("Listbox Demo", 480, 380)

    g_input = guiTextInput(win, 24, 24, 432, 30)

    let bAdd = guiButton(win, "Add",            24, 64, 136, 32)
    let bClr = guiButton(win, "Clear",         172, 64, 136, 32)
    let bUse = guiButton(win, "Show selected", 320, 64, 136, 32)
    guiOnClick(bAdd, funcptr(onAdd))
    guiOnClick(bClr, funcptr(onClear))
    guiOnClick(bUse, funcptr(onShowSelected))

    g_list = guiListbox(win, 24, 108, 432, 240)

    guiShow(win)
    guiRun()
}
