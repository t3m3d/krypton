// 10_menu.k — top menu bar with proper dropdowns.
//
// Three-level model:
//   guiMenuBegin(window)         — attach a menu bar, returns it
//   guiMenu(menubar, "File")     — create a dropdown column, returns popup
//   guiMenuItem(popup, "New")    — add a clickable item, returns id
//   guiMenuSeparator(popup)      — visual divider line
//
// Each item id wires the same way as a button — guiOnClick.

import "stdlib/gui.k"


func onNew()  { guiMessageBox("Menu", "File: New") }
func onOpen() { guiMessageBox("Menu", "File: Open") }
func onSave() { guiMessageBox("Menu", "File: Save") }
func onCut()  { guiMessageBox("Menu", "Edit: Cut") }
func onCopy() { guiMessageBox("Menu", "Edit: Copy") }
func onPaste(){ guiMessageBox("Menu", "Edit: Paste") }
func onAbout(){ guiMessageBox("About", "Krypton menu demo") }
func onQuit() { guiQuit() }


just run {
    guiInit()
    let win = guiWindow("Menu Demo", 480, 240)

    let menubar = guiMenuBegin(win)

    // File dropdown
    let m_file = guiMenu(menubar, "File")
    let mNew  = guiMenuItem(m_file, "New")
    let mOpen = guiMenuItem(m_file, "Open")
    let mSave = guiMenuItem(m_file, "Save")
    guiMenuSeparator(m_file)
    let mQuit = guiMenuItem(m_file, "Quit")
    guiOnClick(mNew,  funcptr(onNew))
    guiOnClick(mOpen, funcptr(onOpen))
    guiOnClick(mSave, funcptr(onSave))
    guiOnClick(mQuit, funcptr(onQuit))

    // Edit dropdown
    let m_edit = guiMenu(menubar, "Edit")
    let mCut   = guiMenuItem(m_edit, "Cut")
    let mCopy  = guiMenuItem(m_edit, "Copy")
    let mPaste = guiMenuItem(m_edit, "Paste")
    guiOnClick(mCut,   funcptr(onCut))
    guiOnClick(mCopy,  funcptr(onCopy))
    guiOnClick(mPaste, funcptr(onPaste))

    // Help dropdown
    let m_help = guiMenu(menubar, "Help")
    let mAbout = guiMenuItem(m_help, "About")
    guiOnClick(mAbout, funcptr(onAbout))

    guiLabel(win, "Use the menu bar at the top.", 24, 24, 420, 22)

    guiShow(win)
    guiRun()
}
