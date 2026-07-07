// stdlib/objk.k -- Objective-K facade for native macOS apps.
//
// Purpose: app code imports one Krypton module and uses ok* APIs.
// Choc is the backend surface; platform legacy stays behind that layer.

module objk

import "k:choc_macos"
import "k:objk_layout"

// App/window
func okApp()                         { emit chocInit() }
func okSharedApp()                   { emit chocSharedApp() }
func okRun(app)                      { emit chocRun(app) }
func okQuit(app)                     { emit chocQuit(app) }
func okFinish(app)                   { emit chocFinishLaunching(app) }
func okPump(app)                     { emit chocPumpEvents(app) }
func okWindow(app, title, w, h)      { let win = chocWindow(app, title, w, h)  emit win + "" }
func okShow(win, app)                { emit chocShow(win, app) }
func okTitle(obj, title)             { emit chocSetTitle(obj, title) }
func okMinSize(win, w, h)            { emit chocSetWindowMinSize(win, w, h) }
func okTransparentTitlebar(win)      { emit chocTransparentTitlebar(win) }
func okMakeFirstResponder(win, view) { emit chocMakeFirstResponder(win, view) }

// Controls
func okButton(win, label, x, y, w, h)      { emit chocButton(win, label, x, y, w, h) }
func okCheckbox(win, label, x, y, w, h)    { emit chocCheckbox(win, label, x, y, w, h) }
func okField(win, x, y, w, h)              { emit chocTextField(win, x, y, w, h) }
func okPassword(win, x, y, w, h)           { emit chocSecureTextField(win, x, y, w, h) }
func okLabel(win, text, x, y, w, h)        { emit chocPlainLabel(win, text, x, y, w, h) }
func okBoxLabel(win, text, x, y, w, h)     { emit chocLabel(win, text, x, y, w, h) }
func okTextView(win, x, y, w, h)           { emit chocScrollText(win, x, y, w, h) }
func okProgress(win, x, y, w, h)           { emit chocProgress(win, x, y, w, h) }
func okSpinner(win, x, y, w, h)            { emit chocProgressSpinner(win, x, y, w, h) }
func okSlider(win, x, y, w, h, mn, mx, v)  { emit chocSlider(win, x, y, w, h, mn, mx, v) }
func okCombo(win, x, y, w, h)              { emit chocComboBox(win, x, y, w, h) }
func okTable(win, x, y, w, h)              { emit chocTable(win, x, y, w, h) }
func okSplit(win, x, y, w, h)              { emit chocSplit(win, x, y, w, h) }
func okSplitAdd(split, view)               { emit chocSplitAdd(split, view) }

// Values/state
func okText(control)                 { emit chocGetText(control) }
func okSetText(control, text)        { emit chocSetText(control, text) }
func okAppend(tv, text)              { emit chocTVAppend(tv, text) }
func okSetTextView(tv, text)         { emit chocTVSetString(tv, text) }
func okTextViewText(tv)              { emit chocTVGetString(tv) }
func okNoWrap(tv)                    { emit chocTVNoWrap(tv) }
func okEnabled(control, enabled)     { emit chocSetEnabled(control, enabled) }
func okHidden(view, hidden)          { emit chocSetHidden(view, hidden) }
func okFrame(view, x, y, w, h)       { emit chocSetFrame(view, x, y, w, h) }
func okToolTip(view, text)           { emit chocSetToolTip(view, text) }
func okEditable(control, editable)   { emit chocSetEditable(control, editable) }
func okSelectable(control, selectable) { emit chocSetSelectable(control, selectable) }
func okBordered(control, bordered)   { emit chocSetBordered(control, bordered) }
func okBezeled(control, bezeled)     { emit chocSetBezeled(control, bezeled) }
func okBackground(control, draws)    { emit chocSetDrawsBackground(control, draws) }
func okPlaceholder(control, text)    { emit chocSetPlaceholder(control, text) }
func okAutoresizing(view, mask)      { emit chocSetAutoresizing(view, mask) }
func okRemove(view)                  { emit chocRemove(view) }
func okState(control)                { emit chocState(control) }
func okSetState(control, state)      { emit chocSetState(control, state) }
func okSetProgress(p, value)         { emit chocSetProgress(p, value) }
func okStart(p)                      { emit chocStartProgress(p) }
func okStop(p)                       { emit chocStopProgress(p) }
func okComboAdd(combo, text)         { emit chocComboAdd(combo, text) }
func okComboSelect(combo, index)     { emit chocComboSelect(combo, index) }
func okComboIndex(combo)             { emit chocComboSelected(combo) }
func okComboText(combo)              { emit chocComboSelectedText(combo) }

// Events/bindings
func okOn(control, key, fnPtr)       { emit chocOnClickKeyed(control, key, fnPtr) }
func okClick(control, fnPtr)         { emit chocOnClick(control, fnPtr) }
func okSet(obj, key, value)          { emit chocSetAssocKey(obj, key, value) }
func okGet(obj, key)                 { emit chocGetAssocKey(obj, key) }
func okSetValue(obj, value)          { emit chocSetAssoc(obj, value) }
func okValue(obj)                    { emit chocGetAssoc(obj) }

// Data containers
func okArray()                       { emit chocArray() }
func okArrayAdd(arr, obj)            { emit chocArrayAdd(arr, obj) }
func okArrayCount(arr)               { emit chocArrayCount(arr) }
func okArrayGet(arr, i)              { emit chocArrayGet(arr, i) }
func okArraySet(arr, i, obj)         { emit chocArraySet(arr, i, obj) }
func okArrayRemove(arr, i)           { emit chocArrayRemove(arr, i) }
func okNumber(n)                     { emit chocNumber(n) }
func okNumberValue(num)              { emit chocNumberVal(num) }

// Files/system
func okChooseFolder(title)           { emit chocChooseFolder(title) }
func okChooseFile(title)             { emit chocChooseFile(title) }
func okSaveFile(title, defaultName)  { emit chocSaveFile(title, defaultName) }
func okClipboard()                   { emit chocClipboardText() }
func okSetClipboard(text)            { emit chocSetClipboardText(text) }
func okDefault(key)                  { emit chocDefaultsGet(key) }
func okSetDefault(key, value)        { emit chocDefaultsSet(key, value) }
func okRemoveDefault(key)            { emit chocDefaultsRemove(key) }
func okOpenURL(url)                  { emit chocOpenURL(url) }
func okOpenPath(path)                { emit chocOpenPath(path) }
func okReveal(path)                  { emit chocRevealPath(path) }

// Theme/color/font
func okDark(obj)                     { emit chocIsDark(obj) }
func okAppearanceName(obj)           { emit chocAppearanceName(obj) }
func okAppearance(obj, name)         { emit chocSetAppearance(obj, name) }
func okColor(name)                   { emit chocColorNamed(name) }
func okRGB(r, g, b)                  { emit chocRGB(r, g, b) }
func okSystemWindowBg()              { emit chocSystemWindowBg() }
func okSystemText()                  { emit chocSystemText() }
func okSystemSecondaryText()         { emit chocSystemSecondaryText() }
func okSystemTextBg()                { emit chocSystemTextBg() }
func okSetBg(view, color)            { emit chocSetBg(view, color) }
func okSetTextColor(view, color)     { emit chocSetTextColor(view, color) }
func okSetWindowBg(win, color)       { emit chocSetWindowBg(win, color) }
func okMonoFont(size)                { emit chocMonoFont(size) }
func okFontFamily(base, family)      { emit chocFontFamily(base, family) }
func okSetFont(view, font)           { emit chocSetFont(view, font) }

// Menus
func okMenuBar(app)                  { emit chocMenuBar(app) }
func okMenuAdd(bar, title)           { emit chocMenuAdd(bar, title) }
func okMenuAction(menu, title, key, fnPtr) { emit chocMenuItem(menu, title, key, fnPtr) }
func okMenuSelector(menu, title, key, selName) { emit chocMenuItemSel(menu, title, key, selName) }
func okMenuSelectorTag(menu, title, key, selName, tag) { emit chocMenuItemSelTag(menu, title, key, selName, tag) }
func okMenuSeparator(menu)           { emit chocMenuSeparator(menu) }
func okSubmenu(menu, title)          { emit chocSubmenuIn(menu, title) }

// Runtime class synthesis for delegates/custom views, still no Obj-C source.
func okClass(name)                   { emit chocClassNew(name) }
func okViewClass(name)               { emit chocViewClassNew(name) }
func okMethod(c, selName, fnPtr, types) { emit chocClassAddMethod(c, selName, fnPtr, types) }
func okRegister(c)                   { emit chocClassRegister(c) }
func okNew(c)                        { emit chocNew(c) }
func okCustomView(win, c, x, y, w, h) { emit chocCustomView(win, c, x, y, w, h) }
func okNeedsDisplay(view)            { emit chocNeedsDisplay(view) }
func okFillRect(x, y, w, h)          { emit chocFillRect(x, y, w, h) }
func okColorSet(color)               { emit chocColorSet(color) }
func okTextAttrs(font, color)        { emit chocTextAttrs(font, color) }
func okDrawText(text, x, y, w, h, attrs) { emit chocDrawText(text, x, y, w, h, attrs) }
