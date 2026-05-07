// gui_widgets.k — showcase of stdlib/gui.k widgets.
//
// Build:
//   kcc.exe examples/gui_widgets.k > tmp.c
//   gcc tmp.c -o gui_widgets.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi \
//       -luxtheme -ladvapi32 -lm -w
//   .\gui_widgets.exe
//
// One window with: text input, multiline text area, checkbox, listbox
// with Add/Clear/Use buttons, a progress bar that the slider buttons
// drive, plus a menu bar with File / Edit / Help that all fire
// callbacks. Stresses every widget in the library.

import "stdlib/gui.k"


let g_input  = ""
let g_area   = ""
let g_check  = ""
let g_list   = ""
let g_prog   = ""
let g_pct    = 0


// Buttons / menu callbacks read these globals.

func onAdd() {
    let s = guiGetText(g_input)
    if len(s) > 0 {
        guiListAdd(g_list, s)
        guiSetText(g_input, "")
    }
}

func onClear() {
    guiListClear(g_list)
}

func onUseSelected() {
    let pick = guiListSelected(g_list)
    if len(pick) == 0 {
        guiMessageBox("Krypton", "Select an item first.")
    } else {
        let lower_ok = guiIsChecked(g_check)
        let txt = pick
        if lower_ok == "1" { txt = toLower(pick) }
        guiSetText(g_area, "Picked: " + txt)
    }
}

func onProgPlus() {
    g_pct = g_pct + 10
    if g_pct > 100 { g_pct = 100 }
    guiProgressSet(g_prog, g_pct)
}

func onProgMinus() {
    g_pct = g_pct - 10
    if g_pct < 0 { g_pct = 0 }
    guiProgressSet(g_prog, g_pct)
}

func onMenuFileNew()    { guiSetText(g_area, "menu: File ▸ New") }
func onMenuFileOpen()   { guiSetText(g_area, "menu: File ▸ Open") }
func onMenuEditClear()  { guiSetText(g_area, "")  guiListClear(g_list) }
func onMenuHelpAbout()  { guiMessageBox("About", "Krypton GUI widgets demo") }
func onMenuFileQuit()   { guiQuit() }


just run {
    guiInit()
    let win = guiWindow("Krypton — Widgets Showcase", 720, 520)

    // Menu bar: flat top-level items. Each gets its own callback.
    let menu = guiMenuBegin(win)
    let mNew   = guiMenuAdd(menu, "File: New")
    let mOpen  = guiMenuAdd(menu, "File: Open")
    let mClear = guiMenuAdd(menu, "Edit: Clear")
    let mAbout = guiMenuAdd(menu, "Help: About")
    let mQuit  = guiMenuAdd(menu, "File: Quit")
    guiOnClick(mNew,   funcptr(onMenuFileNew))
    guiOnClick(mOpen,  funcptr(onMenuFileOpen))
    guiOnClick(mClear, funcptr(onMenuEditClear))
    guiOnClick(mAbout, funcptr(onMenuHelpAbout))
    guiOnClick(mQuit,  funcptr(onMenuFileQuit))

    // ── Left column: input + list controls ────────────────────
    guiLabel(win, "Item:",                        24, 24, 200, 20)
    g_input = guiTextInput(win,                   24, 48, 320, 30)

    let bAdd = guiButton(win, "Add",              24, 88, 100, 32)
    let bClr = guiButton(win, "Clear",           134, 88, 100, 32)
    let bUse = guiButton(win, "Use selection",   244, 88, 100, 32)
    guiOnClick(bAdd, funcptr(onAdd))
    guiOnClick(bClr, funcptr(onClear))
    guiOnClick(bUse, funcptr(onUseSelected))

    g_check = guiCheckbox(win, "lowercase the picked item", 24, 130, 320, 24)

    g_list  = guiListbox(win,                     24, 162, 320, 200)

    // ── Right column: text area + progress ─────────────────────
    guiLabel(win, "Notes:",                       368, 24, 320, 20)
    g_area  = guiTextArea(win,                    368, 48, 320, 240)

    guiLabel(win, "Progress:",                    368, 300, 320, 20)
    g_prog  = guiProgress(win,                    368, 324, 320, 18)
    let bP = guiButton(win, "+10",                368, 354, 152, 32)
    let bM = guiButton(win, "-10",                536, 354, 152, 32)
    guiOnClick(bP, funcptr(onProgPlus))
    guiOnClick(bM, funcptr(onProgMinus))

    guiLabel(win, "Krypton stdlib/gui.k", 24, 392, 664, 18)

    guiShow(win)
    guiRun()
}
