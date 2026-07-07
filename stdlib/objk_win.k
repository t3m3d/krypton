// stdlib/objk_win.k -- Objective-K facade for native Windows apps.
//
// This is the Windows sibling of stdlib/objk.k.  It keeps app code on the
// ok* surface while routing through the proven pure-Krypton Win32 gui module.

module objk_win

import "k:gui"
import "k:shell"

// App/window
func okApp()                    { guiInit()  guiEnableModernChrome()  emit "1" }
func okSharedApp()              { emit okApp() }
func okRun(app)                 { emit guiRun() }
func okQuit(app)                { guiQuit()  emit "1" }
func okFinish(app)              { emit "1" }
func okPump(app)                { emit "0" }
func okWindow(app, title, w, h) { emit guiWindow(title, w, h) }
func okShow(win, app)           { emit guiShow(win) }
func okTitle(obj, title)        { emit guiSetText(obj, title) }
func okMinSize(win, w, h)       { emit "1" }
func okTransparentTitlebar(win) { guiEnableDarkTitle(win)  emit "1" }
func okMakeFirstResponder(win, view) { emit "1" }

// Controls
func okButton(win, label, x, y, w, h)     { emit guiButton(win, label, x, y, w, h) }
func okCheckbox(win, label, x, y, w, h)   { emit guiCheckbox(win, label, x, y, w, h) }
func okField(win, x, y, w, h)             { emit guiTextInput(win, x, y, w, h) }
func okPassword(win, x, y, w, h)          { emit guiPasswordInput(win, x, y, w, h) }
func okLabel(win, text, x, y, w, h)       { emit guiLabel(win, text, x, y, w, h) }
func okBoxLabel(win, text, x, y, w, h)    { emit guiLabel(win, text, x, y, w, h) }
func okTextView(win, x, y, w, h)          { emit guiTextArea(win, x, y, w, h) }
func okProgress(win, x, y, w, h)          { emit guiProgress(win, x, y, w, h) }
func okSpinner(win, x, y, w, h)           { emit guiProgress(win, x, y, w, h) }
func okSlider(win, x, y, w, h, mn, mx, v) {
    let s = guiSlider(win, x, y, w, h)
    guiSliderRange(s, mn, mx)
    guiSliderSet(s, v)
    emit s
}
func okCombo(win, x, y, w, h)             { emit guiCombo(win, x, y, w, h) }
func okTable(win, x, y, w, h)             { emit guiListbox(win, x, y, w, h) }
func okSplit(win, x, y, w, h)             { emit "0" }
func okSplitAdd(split, view)              { emit "0" }

// Values/state
func okText(control)                { emit guiGetText(control) }
func okSetText(control, text)       { emit guiSetText(control, text) }
func okAppend(tv, text)             { emit guiSetText(tv, guiGetText(tv) + text) }
func okSetTextView(tv, text)        { emit guiSetText(tv, text) }
func okTextViewText(tv)             { emit guiGetText(tv) }
func okNoWrap(tv)                   { emit "1" }
func okEnabled(control, enabled)    { emit "1" }
func okHidden(view, hidden)         { emit "1" }
func okFrame(view, x, y, w, h)      { emit "1" }
func okToolTip(view, text)          { emit "1" }
func okEditable(control, editable)  { emit "1" }
func okSelectable(control, selectable) { emit "1" }
func okBordered(control, bordered)  { emit "1" }
func okBezeled(control, bezeled)    { emit "1" }
func okBackground(control, draws)   { emit "1" }
func okPlaceholder(control, text)   { emit "1" }
func okAutoresizing(view, mask)     { emit "1" }
func okRemove(view)                 { emit "1" }
func okState(control)               { emit guiIsChecked(control) }
func okSetState(control, state)     { emit guiSetChecked(control, state) }
func okSetProgress(p, value)        { emit guiProgressSet(p, value) }
func okStart(p)                     { emit "1" }
func okStop(p)                      { emit "1" }
func okComboAdd(combo, text)        { emit guiComboAdd(combo, text) }
func okComboSelect(combo, index)    { emit guiComboSet(combo, index) }
func okComboIndex(combo)            { emit guiComboSelected(combo) }
func okComboText(combo)             { emit guiComboSelected(combo) }

// Events/bindings
func okOn(control, key, fnPtr)      { emit guiOnClick(control, fnPtr) }
func okClick(control, fnPtr)        { emit guiOnClick(control, fnPtr) }
func okSet(obj, key, value)         { emit guiStateSet("ok." + obj + "." + key, value) }
func okGet(obj, key)                { emit guiStateGet("ok." + obj + "." + key) }
func okSetValue(obj, value)         { emit okSet(obj, "value", value) }
func okValue(obj)                   { emit okGet(obj, "value") }

// Data containers: minimal state-list helpers for small app models.
func okArray() {
    let id = guiStateGet("ok.array.next")
    if id == "" { id = "1" }
    guiStateSet("ok.array.next", (toInt(id) + 1) + "")
    guiStateSet("ok.array." + id + ".count", "0")
    emit id
}
func okArrayAdd(arr, obj) {
    let n = toInt(guiStateGet("ok.array." + arr + ".count"))
    guiStateSet("ok.array." + arr + "." + n, obj)
    guiStateSet("ok.array." + arr + ".count", (n + 1) + "")
    emit "1"
}
func okArrayCount(arr)              { emit guiStateGet("ok.array." + arr + ".count") }
func okArrayGet(arr, i)             { emit guiStateGet("ok.array." + arr + "." + i) }
func okArraySet(arr, i, obj)        { emit guiStateSet("ok.array." + arr + "." + i, obj) }
func okArrayRemove(arr, i)          { emit "0" }
func okNumber(n)                    { emit n }
func okNumberValue(num)             { emit num }

// Files/system
func okChooseFolder(title)          { emit guiPickFolder(title) }
func okChooseFile(title)            { emit guiOpenFile(title, "All Files|*.*") }
func okSaveFile(title, defaultName) { emit guiSaveFile(title, "All Files|*.*", defaultName) }
func okClipboard()                  { emit "" }
func okSetClipboard(text)           { emit "0" }
func okDefault(key)                 { emit "" }
func okSetDefault(key, value)       { emit "0" }
func okRemoveDefault(key)           { emit "0" }
func okOpenURL(url)                 { emit shellOpenUrl(url) }
func okOpenPath(path)               { emit shellOpen(path) }
func okReveal(path)                 { emit shellRevealInExplorer(path) }

// Theme/color/font
func okDark(obj)                    { emit "1" }
func okAppearanceName(obj)          { emit "Windows" }
func okAppearance(obj, name)        { emit "1" }
func okColor(name)                  { emit name }
func okRGB(r, g, b)                 { emit "0x" + _okHex2(r) + _okHex2(g) + _okHex2(b) }
func okSystemWindowBg()             { emit "0x241B3B" }
func okSystemText()                 { emit "0xF8F5FF" }
func okSystemSecondaryText()        { emit "0xBEB4E8" }
func okSystemTextBg()               { emit "0x101014" }
func okSetBg(view, color)           { emit "1" }
func okSetTextColor(view, color)    { emit "1" }
func okSetWindowBg(win, color)      { emit guiSetWindowBg(color) }
func okMonoFont(size)               { emit "Consolas" }
func okFontFamily(base, family)     { emit family }
func okSetFont(view, font)          { emit guiSetUiFont(font, "10") }

// Menus: use gui.k flat menu items for now.
func okMenuBar(app)                 { emit guiMenuBegin(guiStateGet("main.hwnd")) }
func okMenuAdd(bar, title)          { emit bar }
func okMenuAction(menu, title, key, fnPtr) {
    let item = guiMenuAdd(menu, title)
    guiOnClick(item, fnPtr)
    emit item
}
func okMenuSelector(menu, title, key, selName) { emit guiMenuAdd(menu, title) }
func okMenuSelectorTag(menu, title, key, selName, tag) { emit guiMenuAdd(menu, title) }
func okMenuSeparator(menu)          { emit "1" }
func okSubmenu(menu, title)         { emit menu }

// Runtime class synthesis is Cocoa-specific.  Keep stubs so portable code can
// probe/link, but real Windows custom views should use gui.k controls today.
func okClass(name)                  { emit "0" }
func okViewClass(name)              { emit "0" }
func okMethod(c, selName, fnPtr, types) { emit "0" }
func okRegister(c)                  { emit "0" }
func okNew(c)                       { emit "0" }
func okCustomView(win, c, x, y, w, h) { emit "0" }
func okNeedsDisplay(view)           { emit "0" }
func okFillRect(x, y, w, h)         { emit "0" }
func okColorSet(color)              { emit "0" }
func okTextAttrs(font, color)       { emit "0" }
func okDrawText(text, x, y, w, h, attrs) { emit "0" }

func _okHexDigit(n) {
    if n < 10 { emit chr(48 + n) }
    emit chr(55 + n)
}

func _okHex2(n) {
    let v = toInt(n)
    let hi = v / 16
    let lo = v - hi * 16
    emit _okHexDigit(hi) + _okHexDigit(lo)
}
