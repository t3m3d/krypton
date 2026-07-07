// stdlib/objk.k -- Objective-K facade for native macOS apps.
//
// Purpose: app code imports one Krypton module and uses ok* APIs.
// Raw objc_msgSend / class names / selectors stay behind stdlib.

module objk

import "k:cocoa"
import "k:objc"
import "k:objk_layout"
import "head:cocoa"
import "head:objc"

// App/window
func okApp()                         { emit cocoaInit() }
func okSharedApp()                   { emit cocoaSharedApp() }
func okRun(app)                      { emit cocoaRun(app) }
func okQuit(app)                     { emit cocoaQuit(app) }
func okFinish(app)                   { emit cocoaFinishLaunching(app) }
func okPump(app)                     { emit cocoaPumpEvents(app) }
func okWindow(app, title, w, h)      { emit cocoaWindow(app, title, w, h) }
func okShow(win, app)                { emit cocoaShow(win, app) }
func okTitle(obj, title)             { emit cocoaSetTitle(obj, title) }
func okMinSize(win, w, h)            { emit cocoaSetWindowMinSize(win, w, h) }
func okTransparentTitlebar(win)      { emit cocoaTransparentTitlebar(win) }
func okMakeFirstResponder(win, view) { emit cocoaMakeFirstResponder(win, view) }

// Controls
func okButton(win, label, x, y, w, h)      { emit cocoaButton(win, label, x, y, w, h) }
func okCheckbox(win, label, x, y, w, h)    { emit cocoaCheckbox(win, label, x, y, w, h) }
func okField(win, x, y, w, h)              { emit cocoaTextField(win, x, y, w, h) }
func okPassword(win, x, y, w, h)           { emit cocoaSecureTextField(win, x, y, w, h) }
func okLabel(win, text, x, y, w, h)        { emit cocoaPlainLabel(win, text, x, y, w, h) }
func okBoxLabel(win, text, x, y, w, h)     { emit cocoaLabel(win, text, x, y, w, h) }
func okTextView(win, x, y, w, h)           { emit cocoaScrollText(win, x, y, w, h) }
func okProgress(win, x, y, w, h)           { emit cocoaProgress(win, x, y, w, h) }
func okSpinner(win, x, y, w, h)            { emit cocoaProgressSpinner(win, x, y, w, h) }
func okSlider(win, x, y, w, h, mn, mx, v)  { emit cocoaSlider(win, x, y, w, h, mn, mx, v) }
func okCombo(win, x, y, w, h)              { emit cocoaComboBox(win, x, y, w, h) }
func okTable(win, x, y, w, h)              { emit cocoaTable(win, x, y, w, h) }
func okSplit(win, x, y, w, h)              { emit cocoaSplit(win, x, y, w, h) }
func okSplitAdd(split, view)               { emit cocoaSplitAdd(split, view) }

// Values/state
func okText(control)                 { emit cocoaGetText(control) }
func okSetText(control, text)        { emit cocoaSetText(control, text) }
func okAppend(tv, text)              { emit cocoaTVAppend(tv, text) }
func okSetTextView(tv, text)         { emit cocoaTVSetString(tv, text) }
func okTextViewText(tv)              { emit cocoaTVGetString(tv) }
func okNoWrap(tv)                    { emit cocoaTVNoWrap(tv) }
func okEnabled(control, enabled)     { emit cocoaSetEnabled(control, enabled) }
func okHidden(view, hidden)          { emit cocoaSetHidden(view, hidden) }
func okFrame(view, x, y, w, h)       { emit cocoaSetFrame(view, x, y, w, h) }
func okToolTip(view, text)           { emit cocoaSetToolTip(view, text) }
func okEditable(control, editable)   { emit cocoaSetEditable(control, editable) }
func okSelectable(control, selectable) { emit cocoaSetSelectable(control, selectable) }
func okBordered(control, bordered)   { emit cocoaSetBordered(control, bordered) }
func okBezeled(control, bezeled)     { emit cocoaSetBezeled(control, bezeled) }
func okBackground(control, draws)    { emit cocoaSetDrawsBackground(control, draws) }
func okPlaceholder(control, text)    { emit cocoaSetPlaceholder(control, text) }
func okAutoresizing(view, mask)      { emit cocoaSetAutoresizing(view, mask) }
func okRemove(view)                  { emit cocoaRemove(view) }
func okState(control)                { emit cocoaState(control) }
func okSetState(control, state)      { emit cocoaSetState(control, state) }
func okSetProgress(p, value)         { emit cocoaSetProgress(p, value) }
func okStart(p)                      { emit cocoaStartProgress(p) }
func okStop(p)                       { emit cocoaStopProgress(p) }
func okComboAdd(combo, text)         { emit cocoaComboAdd(combo, text) }
func okComboSelect(combo, index)     { emit cocoaComboSelect(combo, index) }
func okComboIndex(combo)             { emit cocoaComboSelected(combo) }
func okComboText(combo)              { emit cocoaComboSelectedText(combo) }

// Events/bindings
func okOn(control, key, fnPtr)       { emit cocoaOnClickKeyed(control, key, fnPtr) }
func okClick(control, fnPtr)         { emit cocoaOnClick(control, fnPtr) }
func okSet(obj, key, value)          { emit cocoaSetAssocKey(obj, key, value) }
func okGet(obj, key)                 { emit cocoaGetAssocKey(obj, key) }
func okSetValue(obj, value)          { emit cocoaSetAssoc(obj, value) }
func okValue(obj)                    { emit cocoaGetAssoc(obj) }

// Data containers
func okArray()                       { emit cocoaArray() }
func okArrayAdd(arr, obj)            { emit cocoaArrayAdd(arr, obj) }
func okArrayCount(arr)               { emit cocoaArrayCount(arr) }
func okArrayGet(arr, i)              { emit cocoaArrayGet(arr, i) }
func okArraySet(arr, i, obj)         { emit cocoaArraySet(arr, i, obj) }
func okArrayRemove(arr, i)           { emit cocoaArrayRemove(arr, i) }
func okNumber(n)                     { emit cocoaNumber(n) }
func okNumberValue(num)              { emit cocoaNumberVal(num) }

// Files/system
func okChooseFolder(title)           { emit cocoaChooseFolder(title) }
func okChooseFile(title)             { emit cocoaChooseFile(title) }
func okSaveFile(title, defaultName)  { emit cocoaSaveFile(title, defaultName) }
func okClipboard()                   { emit cocoaClipboardText() }
func okSetClipboard(text)            { emit cocoaSetClipboardText(text) }
func okDefault(key)                  { emit cocoaDefaultsGet(key) }
func okSetDefault(key, value)        { emit cocoaDefaultsSet(key, value) }
func okRemoveDefault(key)            { emit cocoaDefaultsRemove(key) }
func okOpenURL(url)                  { emit cocoaOpenURL(url) }
func okOpenPath(path)                { emit cocoaOpenPath(path) }
func okReveal(path)                  { emit cocoaRevealPath(path) }

// Theme/color/font
func okDark(obj)                     { emit cocoaIsDark(obj) }
func okAppearanceName(obj)           { emit cocoaAppearanceName(obj) }
func okAppearance(obj, name)         { emit cocoaSetAppearance(obj, name) }
func okColor(name)                   { emit cocoaColorNamed(name) }
func okRGB(r, g, b)                  { emit cocoaRGB(r, g, b) }
func okSystemWindowBg()              { emit cocoaSystemWindowBg() }
func okSystemText()                  { emit cocoaSystemText() }
func okSystemSecondaryText()         { emit cocoaSystemSecondaryText() }
func okSystemTextBg()                { emit cocoaSystemTextBg() }
func okSetBg(view, color)            { emit cocoaSetBg(view, color) }
func okSetTextColor(view, color)     { emit cocoaSetTextColor(view, color) }
func okSetWindowBg(win, color)       { emit cocoaSetWindowBg(win, color) }
func okMonoFont(size)                { emit cocoaMonoFont(size) }
func okFontFamily(base, family)      { emit cocoaFontFamily(base, family) }
func okSetFont(view, font)           { emit cocoaSetFont(view, font) }

// Menus
func okMenuBar(app)                  { emit cocoaMenuBar(app) }
func okMenuAdd(bar, title)           { emit cocoaMenuAdd(bar, title) }
func okMenuAction(menu, title, key, fnPtr) { emit cocoaMenuItem(menu, title, key, fnPtr) }
func okMenuSelector(menu, title, key, selName) { emit cocoaMenuItemSel(menu, title, key, selName) }
func okMenuSelectorTag(menu, title, key, selName, tag) { emit cocoaMenuItemSelTag(menu, title, key, selName, tag) }
func okMenuSeparator(menu)           { emit cocoaMenuSeparator(menu) }
func okSubmenu(menu, title)          { emit cocoaSubmenuIn(menu, title) }

// Runtime class synthesis for delegates/custom views, still no Obj-C source.
func okClass(name)                   { emit cocoaClassNew(name) }
func okViewClass(name)               { emit cocoaViewClassNew(name) }
func okMethod(c, selName, fnPtr, types) { emit cocoaClassAddMethod(c, selName, fnPtr, types) }
func okRegister(c)                   { emit cocoaClassRegister(c) }
func okNew(c)                        { emit cocoaNew(c) }
func okCustomView(win, c, x, y, w, h) { emit cocoaCustomView(win, c, x, y, w, h) }
func okNeedsDisplay(view)            { emit cocoaNeedsDisplay(view) }
func okFillRect(x, y, w, h)          { emit cocoaFillRect(x, y, w, h) }
func okColorSet(color)               { emit cocoaColorSet(color) }
func okTextAttrs(font, color)        { emit cocoaTextAttrs(font, color) }
func okDrawText(text, x, y, w, h, attrs) { emit cocoaDrawText(text, x, y, w, h, attrs) }
