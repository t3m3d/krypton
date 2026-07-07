// stdlib/choc.k -- Choc native UI kit for Krypton (Windows backend slice).
//
// Choc is the shared native UI kit concept. This file is the current Windows
// backend slice: it keeps Win32 GUI/system calls behind a compact Krypton API.

module choc

import "k:gui"
import "k:shell"

// App/window
func chocInit()                    { emit "1" }
func chocRun(app)                  { emit guiRun() }
func chocQuit(app)                 { emit guiQuit() }
func chocFinishLaunching(app)      { emit "1" }
func chocPumpEvents(app)           { emit "0" }
func chocWindow(app, title, w, h)  { let win = guiWindow(title, w, h)  emit win + "" }
func chocShow(win, app)            { emit guiShow(win) }
func chocSetTitle(obj, title)      { emit guiSetText(obj, title) }
func chocTransparentTitlebar(win)  { emit guiEnableDarkTitle(win) }

// Controls
func chocButton(win, label, x, y, w, h)    { emit guiButton(win, label, x, y, w, h) }
func chocCheckbox(win, label, x, y, w, h)  { emit guiCheckbox(win, label, x, y, w, h) }
func chocTextField(win, x, y, w, h)        { emit guiTextInput(win, x, y, w, h) }
func chocSecureTextField(win, x, y, w, h)  { emit guiTextInput(win, x, y, w, h) }
func chocLabel(win, text, x, y, w, h)      { emit guiLabel(win, text, x, y, w, h) }
func chocTextView(win, x, y, w, h)         { emit guiTextArea(win, x, y, w, h) }
func chocProgress(win, x, y, w, h)         { emit guiProgress(win, x, y, w, h) }
func chocSlider(win, x, y, w, h, mn, mx, v) {
    let s = guiSlider(win, x, y, w, h)
    guiSliderRange(s, mn, mx)
    guiSliderSet(s, v)
    emit s
}
func chocComboBox(win, x, y, w, h)         { emit guiCombo(win, x, y, w, h) }
func chocList(win, x, y, w, h)             { emit guiListbox(win, x, y, w, h) }

// Values/state
func chocGetText(control)                  { emit guiGetText(control) }
func chocSetText(control, text)            { emit guiSetText(control, text) }
func chocAppend(tv, text)                  { emit guiSetText(tv, guiGetText(tv) + text) }
func chocState(control)                    { emit guiIsChecked(control) }
func chocSetState(control, state)          { emit guiSetChecked(control, state) }
func chocSetProgress(p, value)             { emit guiProgressSet(p, value) }
func chocComboAdd(combo, text)             { emit guiComboAdd(combo, text) }
func chocComboSelect(combo, index)         { emit guiComboSet(combo, index) }
func chocComboIndex(combo)                 { emit guiComboSelected(combo) }
func chocComboText(combo)                  { emit guiComboSelected(combo) }

// Events. guiOnClick dispatches Obj-K-shaped args ("", "", senderId).
func chocOnClick(control, fnPtr)           { emit guiOnClick(control, fnPtr) }
func chocStateSet(key, value)              { emit guiStateSet(key, value) }
func chocStateGet(key)                     { emit guiStateGet(key) }
func chocSetAssoc(obj, key, value)         { emit guiStateSet("ok." + obj + "." + key, value) }
func chocGetAssoc(obj, key)                { emit guiStateGet("ok." + obj + "." + key) }

// Menus
func chocMenuBar(app)                      { emit guiMenuBegin(guiStateGet("main.hwnd")) }
func chocMenuAdd(menu, title)              { emit guiMenuAdd(menu, title) }
func chocMenuAction(menu, title, fnPtr) {
    let item = guiMenuAdd(menu, title)
    guiOnClick(item, fnPtr)
    emit item
}

// Files/system
func chocChooseFolder(title)               { emit guiPickFolder(title) }
func chocChooseFile(title)                 { emit guiOpenFile(title, "All Files|*.*") }
func chocSaveFile(title, defaultName)      { emit guiSaveFile(title, "All Files|*.*", defaultName) }
func chocOpenURL(url)                      { emit shellOpenUrl(url) }
func chocOpenPath(path)                    { emit shellOpen(path) }
func chocReveal(path)                      { emit shellRevealInExplorer(path) }

// Theme/color/font
func chocSystemWindowBg()                  { emit "0x241B3B" }
func chocSystemText()                      { emit "0xF8F5FF" }
func chocSystemSecondaryText()             { emit "0xBEB4E8" }
func chocSystemTextBg()                    { emit "0x101014" }
func chocSetWindowBg(win, color)           { emit guiSetWindowBg(color) }
func chocSetFont(view, font)               { emit guiSetUiFont(font, "10") }
