// stdlib/objkwin.k -- Objective-K facade for native Windows apps.
//
// This is the Windows sibling of stdlib/objk.k. It keeps app code on the
// ok* surface while routing through Choc, the Windows peer to Cocoa.

module objkwin

import "k:choc"
import "k:objk_layout"

// App/window
func okApp()                    { emit chocInit() }
func okSharedApp()              { emit okApp() }
func okRun(app)                 { emit chocRun(app) }
func okQuit(app)                { emit chocQuit(app) }
func okFinish(app)              { emit chocFinishLaunching(app) }
func okPump(app)                { emit chocPumpEvents(app) }
func okWindow(app, title, w, h) { let win = chocWindow(app, title, w, h)  emit win + "" }
func okShow(win, app)           { emit chocShow(win, app) }
func okTitle(obj, title)        { emit chocSetTitle(obj, title) }
func okMinSize(win, w, h)       { emit "1" }
func okTransparentTitlebar(win) { emit chocTransparentTitlebar(win) }
func okMakeFirstResponder(win, view) { emit "1" }

// Controls
func okButton(win, label, x, y, w, h)     { emit chocButton(win, label, x, y, w, h) }
func okCheckbox(win, label, x, y, w, h)   { emit chocCheckbox(win, label, x, y, w, h) }
func okField(win, x, y, w, h)             { emit chocTextField(win, x, y, w, h) }
func okPassword(win, x, y, w, h)          { emit chocSecureTextField(win, x, y, w, h) }
func okLabel(win, text, x, y, w, h)       { emit chocLabel(win, text, x, y, w, h) }
func okBoxLabel(win, text, x, y, w, h)    { emit chocLabel(win, text, x, y, w, h) }
func okTextView(win, x, y, w, h)          { emit chocTextView(win, x, y, w, h) }
func okProgress(win, x, y, w, h)          { emit chocProgress(win, x, y, w, h) }
func okSpinner(win, x, y, w, h)           { emit chocProgress(win, x, y, w, h) }
func okSlider(win, x, y, w, h, mn, mx, v) { emit chocSlider(win, x, y, w, h, mn, mx, v) }
func okCombo(win, x, y, w, h)             { emit chocComboBox(win, x, y, w, h) }
func okTable(win, x, y, w, h)             { emit chocList(win, x, y, w, h) }
func okSplit(win, x, y, w, h)             { emit "0" }
func okSplitAdd(split, view)              { emit "0" }

// Values/state
func okText(control)                { emit chocGetText(control) }
func okSetText(control, text)       { emit chocSetText(control, text) }
func okAppend(tv, text)             { emit chocAppend(tv, text) }
func okSetTextView(tv, text)        { emit chocSetText(tv, text) }
func okTextViewText(tv)             { emit chocGetText(tv) }
func okNoWrap(tv)                   { emit "1" }
func okTextLength(tv)               { emit len(chocGetText(tv)) }
func okTextColorRange(tv, color, loc, n) { emit chocTextColorRange(tv, color, loc, n) }
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
func okState(control)               { emit chocState(control) }
func okSetState(control, state)     { emit chocSetState(control, state) }
func okSetProgress(p, value)        { emit chocSetProgress(p, value) }
func okStart(p)                     { emit "1" }
func okStop(p)                      { emit "1" }
func okComboAdd(combo, text)        { emit chocComboAdd(combo, text) }
func okComboSelect(combo, index)    { emit chocComboSelect(combo, index) }
func okComboIndex(combo)            { emit chocComboIndex(combo) }
func okComboText(combo)             { emit chocComboText(combo) }

// Events/bindings
func okOn(control, key, fnPtr)      { emit chocOnClick(control, fnPtr) }
func okClick(control, fnPtr)        { emit chocOnClick(control, fnPtr) }
func okSet(obj, key, value)         { emit chocSetAssoc(obj, key, value) }
func okGet(obj, key)                { emit chocGetAssoc(obj, key) }
func okSetValue(obj, value)         { emit okSet(obj, "value", value) }
func okValue(obj)                   { emit okGet(obj, "value") }

// Data containers: minimal state-list helpers for small app models.
func okArray() {
    let id = chocStateGet("ok.array.next")
    if id == "" { id = "1" }
    chocStateSet("ok.array.next", (toInt(id) + 1) + "")
    chocStateSet("ok.array." + id + ".count", "0")
    emit id
}
func okArrayAdd(arr, obj) {
    let n = toInt(chocStateGet("ok.array." + arr + ".count"))
    chocStateSet("ok.array." + arr + "." + n, obj)
    chocStateSet("ok.array." + arr + ".count", (n + 1) + "")
    emit "1"
}
func okArrayCount(arr)              { emit chocStateGet("ok.array." + arr + ".count") }
func okArrayGet(arr, i)             { emit chocStateGet("ok.array." + arr + "." + i) }
func okArraySet(arr, i, obj)        { emit chocStateSet("ok.array." + arr + "." + i, obj) }
func okArrayRemove(arr, i)          { emit "0" }
func okNumber(n)                    { emit n }
func okNumberValue(num)             { emit num }

// Files/system
func okChooseFolder(title)          { emit chocChooseFolder(title) }
func okChooseFile(title)            { emit chocChooseFile(title) }
func okSaveFile(title, defaultName) { emit chocSaveFile(title, defaultName) }
func okClipboard()                  { emit "" }
func okSetClipboard(text)           { emit "0" }
func okDefault(key)                 { emit "" }
func okSetDefault(key, value)       { emit "0" }
func okRemoveDefault(key)           { emit "0" }
func okOpenURL(url)                 { emit chocOpenURL(url) }
func okOpenPath(path)               { emit chocOpenPath(path) }
func okReveal(path)                 { emit chocReveal(path) }

// Theme/color/font
func okDark(obj)                    { emit "1" }
func okAppearanceName(obj)          { emit "Windows" }
func okAppearance(obj, name)        { emit "1" }
func okColor(name)                  { emit name }
func okRGB(r, g, b)                 { emit "0x" + _okHex2(r) + _okHex2(g) + _okHex2(b) }
func okSystemWindowBg()             { emit chocSystemWindowBg() }
func okSystemText()                 { emit chocSystemText() }
func okSystemSecondaryText()        { emit chocSystemSecondaryText() }
func okSystemTextBg()               { emit chocSystemTextBg() }
func okSetBg(view, color)           { emit "1" }
func okSetTextColor(view, color)    { emit "1" }
func okSetButtonTextColor(btn, color) { emit chocSetButtonTextColor(btn, color) }
func okSetWindowBg(win, color)      { emit chocSetWindowBg(win, color) }
func okMonoFont(size)               { emit "Consolas" }
func okFontFamily(base, family)     { emit family }
func okSetFont(view, font)          { emit chocSetFont(view, font) }
func okAlert(title, message)        { emit chocAlert(title, message) }

// Menus: use Choc flat menu items for now.
func okMenuBar(app)                 { emit chocMenuBar(app) }
func okMenuAdd(bar, title)          { emit bar }
func okMenuAction(menu, title, key, fnPtr) {
    emit chocMenuAction(menu, title, fnPtr)
}
func okMenuSelector(menu, title, key, selName) { emit chocMenuAdd(menu, title) }
func okMenuSelectorTag(menu, title, key, selName, tag) { emit chocMenuAdd(menu, title) }
func okMenuSeparator(menu)          { emit chocMenuSeparator(menu) }
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
