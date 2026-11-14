// Copyright 2026 The Krypton Authors.
// Licensed under the Apache License, Version 2.0 (see LICENSE or
// http://www.apache.org/licenses/LICENSE-2.0).
module objk

import "k:choc_macos"
import "k:objk_layout"
import "k:objc"

func okApp()                         { emit chocInit() }
func okSharedApp()                   { emit chocSharedApp() }
func okRun(app)                      { emit chocRun(app) }
func okQuit(app)                     { emit chocQuit(app) }
func okFinish(app)                   { emit chocFinishLaunching(app) }
func okPump(app)                     { emit chocPumpEvents(app) }
func okWindow(app, title, w, h)      { emit chocWindow(app, title, w, h) }
func okShow(win, app)                { emit chocShow(win, app) }
func okTitle(obj, title)             { emit chocSetTitle(obj, title) }
func okMinSize(win, w, h)            { emit chocSetWindowMinSize(win, w, h) }
func okTransparentTitlebar(win)      { emit chocTransparentTitlebar(win) }
func okMakeFirstResponder(win, view) { emit chocMakeFirstResponder(win, view) }
func okWindowShouldClose(win, fnPtr) { emit chocWindowShouldClose(win, fnPtr) }
func okWindowOnClose(win, fnPtr)     { emit chocWindowOnClose(win, fnPtr) }
func okAppOnOpenFile(app, fnPtr)     { emit chocAppOnOpenFile(app, fnPtr) }
func okAppOnReopen(app, fnPtr)       { emit chocAppOnReopen(app, fnPtr) }

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
func okDataSource(table, source)          { emit chocSetDataSource(table, source) }
func okReload(table)                      { emit chocReload(table) }
func okMultiSelect(table, enabled)        { if table == 0 { emit "0" } msg_1(table, "setAllowsMultipleSelection:", enabled) emit "1" }
func okSelectionNew()                     { emit chocSelectionNew() }
func okSelection(table)                   { emit chocSelection(table) }
func okSelectionCount(rows)               { emit chocSelectionCount(rows) }
func okSelectionAdd(rows, row)            { emit chocSelectionAdd(rows, row) }
func okSelectionAt(rows, offset)          { emit chocSelectionAt(rows, offset) }
func okSelect(table, rows)                { emit chocSelect(table, rows, 0) }
func okSelectExtend(table, rows, extend)  { emit chocSelect(table, rows, extend) }
func okSelectRow(table, row, extend)      { emit chocSelectRow(table, row, extend) }
func okSelectNone(table)                  { if table == 0 { emit "0" } msg_1(table, "deselectAll:", 0) emit "1" }
func okSelectAll(table)                   { if table == 0 { emit "0" } msg_1(table, "selectAll:", 0) emit "1" }
func okScrollTo(table, row)              { emit chocScrollTo(table, row) }
func okOnKeyDown(table, fnPtr)            { emit chocTableOnKeyDown(table, fnPtr) }
func okOnClick(table, fnPtr)              { emit chocTableOnClick(table, fnPtr, 0) }
func okOnDoubleClick(table, fnPtr)        { emit chocTableOnClick(table, fnPtr, 1) }
func okColumn(table, id, title, width)    { emit chocColumn(table, id, title, width) }
func okColWidth(table, id, width)         { emit chocColWidth(table, id, width) }
func okRowHeight(table, height)          { emit chocRowHeight(table, height) }
func okKeyCode(event)                     { emit msg(event, "keyCode") }
func okKeyModifiers(event)                { emit msg(event, "modifierFlags") }
func okKeyText(event)                     { emit nsToStr(msg(event, "characters")) }
func okFieldOnChange(field, fnPtr)        { emit chocFieldOnChange(field, fnPtr) }
func okSplit(win, x, y, w, h)              { emit chocSplit(win, x, y, w, h) }
func okSplitAdd(split, view)               { emit chocSplitAdd(split, view) }

func okSegmented(win, x, y, w, h)         { emit chocSegmented(win, x, y, w, h) }
func okSegCount(seg, n)                   { emit chocSegCount(seg, n) }
func okSegLabel(seg, label, index)        { emit chocSegLabel(seg, label, index) }
func okSegAdd(seg, label) {
    if seg == 0 { emit -1 }
    let index = msg(seg, "segmentCount")
    chocSegCount(seg, index + 1)
    chocSegLabel(seg, label, index)
    emit index
}
func okSegSelect(seg, index) {
    if seg == 0 || index < -1 || index >= msg(seg, "segmentCount") { emit "0" }
    emit chocSegSelect(seg, index)
}
func okSegIndex(seg)                      { emit chocSegSelected(seg) }
func okSegOnChange(seg, fnPtr)            { emit chocOnClick(seg, fnPtr) }

// Snapshot borrowed UTF-8 or builder text before its owner changes or drains.
func okCopyText(text)                { emit substring(text, 0, len(text)) }
func okObjectText(obj)               { emit okCopyText(nsToStr(obj)) }
func okText(control)                 { emit chocGetText(control) }
func okSetText(control, text)        { emit chocSetText(control, text) }
func okAppend(tv, text)              { emit chocTVAppend(tv, text) }
func okSetTextView(tv, text)         { emit chocTVSetString(tv, text) }
func okTextViewText(tv)              { emit chocTVGetString(tv) }
func okNoWrap(tv)                    { emit chocTVNoWrap(tv) }
func okTextLength(tv)                { emit chocTVLength(tv) }
func okTextColorRange(tv, color, loc, n) { emit chocTVColorRange(tv, color, loc, n) }
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

func okOn(control, key, fnPtr)       { emit chocOnClickKeyed(control, key, fnPtr) }
func okClick(control, fnPtr)         { emit chocOnClick(control, fnPtr) }
func okSet(obj, key, value)          { emit chocSetAssocKey(obj, key, value) }
func okGet(obj, key)                 { emit chocGetAssocKey(obj, key) }
func okSetValue(obj, value)          { emit chocSetAssoc(obj, value) }
func okValue(obj)                    { emit chocGetAssoc(obj) }

func okArray()                       { emit chocArray() }
func okArrayAdd(arr, obj)            { emit chocArrayAdd(arr, obj) }
func okArrayCount(arr)               { emit chocArrayCount(arr) }
func okArrayGet(arr, i)              { emit chocArrayGet(arr, i) }
func okArraySet(arr, i, obj)         { emit chocArraySet(arr, i, obj) }
func okArrayRemove(arr, i)           { emit chocArrayRemove(arr, i) }
func okNumber(n)                     { emit chocNumber(n) }
func okNumberValue(num)              { emit chocNumberVal(num) }

func okChooseFolder(title)           { emit chocChooseFolder(title) }
func okChooseFile(title)             { emit chocChooseFile(title) }
func okSaveFile(title, defaultName)  { emit chocSaveFile(title, defaultName) }
func okBundledExecutable(name)       { emit chocBundledExecutable(name) }
func okBundledResource(name)         { emit chocBundledResource(name) }
func okTemporaryDirectory()          { emit chocTemporaryDirectory() }
func okClipboard()                   { emit chocClipboardText() }
func okSetClipboard(text)            { emit chocSetClipboardText(text) }
func okDefault(key)                  { emit chocDefaultsGet(key) }
func okSetDefault(key, value)        { emit chocDefaultsSet(key, value) }
func okRemoveDefault(key)            { emit chocDefaultsRemove(key) }
func okOpenURL(url)                  { emit chocOpenURL(url) }
func okOpenPath(path)                { emit chocOpenPath(path) }
func okReveal(path)                  { emit chocRevealPath(path) }

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
func okSetButtonTextColor(btn, color){ emit chocSetButtonTextColor(btn, color) }
func okSetWindowBg(win, color)       { emit chocSetWindowBg(win, color) }
func okMonoFont(size)                { emit chocMonoFont(size) }
func okFontFamily(base, family)      { emit chocFontFamily(base, family) }
func okSetFont(view, font)           { emit chocSetFont(view, font) }
func okAlert(title, message)         { emit chocAlert(title, message) }
func okImageView(win, x, y, w, h)    { emit chocImageView(win, x, y, w, h) }
func okImageFromFile(view, path)     { emit chocImageFromFile(view, path) }
func okFrameSave(win, key)           { emit chocFrameSave(win, key) }
func okFrameRestore(win, key)        { emit chocFrameRestore(win, key) }

func okMenuBar(app)                  { emit chocMenuBar(app) }
func okMenuAdd(bar, title)           { emit chocMenuAdd(bar, title) }
func okMenuAction(menu, title, key, fnPtr) { emit chocMenuItem(menu, title, key, fnPtr) }
func okMenuSelector(menu, title, key, selName) { emit chocMenuItemSel(menu, title, key, selName) }
func okMenuSelectorTag(menu, title, key, selName, tag) { emit chocMenuItemSelTag(menu, title, key, selName, tag) }
func okMenuSeparator(menu)           { emit chocMenuSeparator(menu) }
func okMenuCheck(menu, title, on)    { emit chocMenuCheck(menu, title, on) }
func okMenuEnabled(menu, title, on)  { emit chocMenuEnabled(menu, title, on) }
func okSubmenu(menu, title)          { emit chocSubmenuIn(menu, title) }

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

func okAutoreleasePool()              { emit newPool() }
func okDrainPool(pool)                { emit drainPool(pool) }
func okImage(size)                    { emit msg_d2(msg(cls("NSImage"), "alloc"), "initWithSize:", size, size) }
func okImageBegin(image)              { emit msg(image, "lockFocus") }
func okImageEnd(image)                { emit msg(image, "unlockFocus") }
func okGraphicsSave()                 { emit msg(cls("NSGraphicsContext"), "saveGraphicsState") }
func okGraphicsRestore()              { emit msg(cls("NSGraphicsContext"), "restoreGraphicsState") }
func okPath()                         { emit msg(cls("NSBezierPath"), "bezierPath") }
func okRoundedPath(x, y, w, h, rx, ry) { emit msg_rounded(cls("NSBezierPath"), "bezierPathWithRoundedRect:xRadius:yRadius:", x, y, w, h, rx, ry) }
func okPathMove(path, x, y)           { emit msg_d2(path, "moveToPoint:", x, y) }
func okPathLine(path, x, y)           { emit msg_d2(path, "lineToPoint:", x, y) }
func okPathWidth(path, width)         { emit msg_d1(path, "setLineWidth:", width) }
func okPathCap(path, style)           { emit msg_1(path, "setLineCapStyle:", style) }
func okPathJoin(path, style)          { emit msg_1(path, "setLineJoinStyle:", style) }
func okPathFill(path)                 { emit msg(path, "fill") }
func okPathStroke(path)               { emit msg(path, "stroke") }
func okRGBA(r, g, b, a)              { emit msg_rgba(cls("NSColor"), "colorWithCalibratedRed:green:blue:alpha:", r, g, b, a) }
func okGradient(startColor, endColor) { emit msg_2(msg(cls("NSGradient"), "alloc"), "initWithStartingColor:endingColor:", startColor, endColor) }
func okGradientPath(gradient, path, angle) { emit msg_pd1(gradient, "drawInBezierPath:angle:", path, angle) }
func okImagePNG(image, path) {
    let tiff = msg(image, "TIFFRepresentation")
    if tiff == 0 { emit 0 }
    let rep = msg_1(cls("NSBitmapImageRep"), "imageRepWithData:", tiff)
    if rep == 0 { emit 0 }
    let props = msg(cls("NSDictionary"), "dictionary")
    let png = msg_2(rep, "representationUsingType:properties:", 4, props)
    if png == 0 { emit 0 }
    emit msg_2(png, "writeToFile:atomically:", nsString(path), 1)
}

// Scroll constructors return document views. Lay out/hide their enclosing
// container without moving the document origin or leaving an empty scroll view.
func okScrollFrame(document, x, y, w, h) {
    let scroll = msg(document, "enclosingScrollView")
    if scroll == 0 { emit "0" }
    emit chocSetFrame(scroll, x, y, w, h)
}
func okScrollHidden(document, hidden) {
    let scroll = msg(document, "enclosingScrollView")
    if scroll == 0 { emit "0" }
    emit chocSetHidden(scroll, hidden)
}

// CGFloat/NSRect values must use the struct-return ABI rather than msg().
func okViewWidth(view) { emit msgRectWidth(view, "bounds") }
func okViewHeight(view) { emit msgRectHeight(view, "bounds") }

// Generic == treats high addresses as text. Compare foreign handles numerically.
func okSameHandle(a, b) { emit (a - b) == 0 }

// ── Short-form Objective-C runtime API ─────────────────────────────
// Concise, idiomatic aliases over the verbose runtime bindings in
// headers/objc.krh. Prefer these for new call sites.
// (cls/sel take a class or selector NAME and cache the resolved handle.)

// Selector memoization: a global structNew-const keyed by selector
// name → registered SEL handle. Rebuilt on each miss via sel().
// Never freed — process-scoped cache, matches the spec.
let okSelCacheMap = 0

// lookup: cached or register-and-memoize.
func okSel(name) {
    if okSelCacheMap == 0 { okSelCacheMap = structNew() }
    let hit = getField(okSelCacheMap, name)
    if hit != 0 { emit hit }
    let s = sel(name)
    setField(okSelCacheMap, name, s)
    emit s
}

func okCls(name) { emit cls(name) }
func okSend(obj, selName) { emit msg(obj, selName) }
func okSend1(obj, selName, a) { emit msg_1(obj, selName, a) }
func okSend2(obj, selName, a, b) { emit msg_2(obj, selName, a, b) }
func okSend3(obj, selName, a, b, c) { emit msg_3(obj, selName, a, b, c) }
func okSendFp(obj, selName) { emit msg_fp(obj, selName) }
func okSendRect(obj, selName, x, y, w, h, mask, backing, deferF) { emit msg_rect(obj, selName, x, y, w, h, mask, backing, deferF) }

// Dynamic subclass creation
func okNewCls(superCls, name) {
    let c = chocClassNew(name)
    emit c
}
func okAddFn(c, selName, fnPtr, types) { emit chocClassAddMethod(c, selName, fnPtr, types) }
func okRegCls(c) { emit chocClassRegister(c) }

// Autorelease pool scoping
func okPoolPush() { emit objc_autoreleasePoolPush() }
func okPoolPop(pool) { objc_autoreleasePoolPop(pool); emit "1" }

// CoreFoundation ↔ Objective-C toll-free bridging helpers
func okCfIn(ref) { emit CFRetain(ref) }
func okCfOut(ref) { CFRelease(ref); emit "1" }

// Zeroing weak references
// `loc` is a bufNew(8) pointer owned by the caller. Only one live weak
// reference per location; do not reuse a location after destroyWeak.
func okWeakSet(loc, obj) { objc_initWeak(loc, obj); emit "1" }
func okWeakGet(loc) { emit objc_loadWeakRetained(loc) }
func okWeakDel(loc) { objc_destroyWeak(loc); emit "1" }

// Explicit association helpers (short aliases for the objc_setAssociatedObject family)
func okSetAssoc(obj, key, value, policy) { objc_setAssociatedObject(obj, sel(key), value, policy); emit "1" }
func okGetAssoc(obj, key) { emit objc_getAssociatedObject(obj, sel(key)) }
