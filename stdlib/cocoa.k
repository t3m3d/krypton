// stdlib/cocoa.k — High-level Cocoa GUI for macOS, written in pure Krypton.
//
// Runs on the objk FFI (macho_arm64_self.k): objc_msgSend + dyld-imported
// libobjc/Foundation/AppKit, NSRect via objc_msgSend_rect/_frame, and Krypton
// funcs used directly as Obj-C method IMPs for callbacks.
//
// IMPORTANT: selector/class strings + enum values are INLINED here, not pulled
// from head:cocoa consts — module-level `const`/`let` does NOT initialise across
// the native import boundary (it reads as garbage), so every literal lives in the
// function that uses it.
//
//   import "k:cocoa"
//   func onClick(self, cmd, sender) { cocoaSetText(cocoaGetAssoc(sender), "hi") }
//   just run {
//       let app = cocoaInit()
//       let win = cocoaWindow(app, "Demo", 400, 220)
//       let btn = cocoaButton(win, "Click me", 150, 90, 100, 30)
//       cocoaSetAssoc(btn, win)
//       cocoaOnClick(btn, funcptr(onClick))
//       cocoaShow(win, app)
//       cocoaRun(app)
//   }

module cocoa

import "k:objc"

// ── App lifecycle ──────────────────────────────────────────────────────

func cocoaInit() {
    let app = msg(cls("NSApplication"), "sharedApplication")
    msg_1(app, "setActivationPolicy:", 0)        // NSApplicationActivationPolicyRegular
    msg_1(app, "activateIgnoringOtherApps:", 1)
    emit app
}

func cocoaSharedApp() { emit msg(cls("NSApplication"), "sharedApplication") }
func cocoaRun(app)  { msg(app, "run")             emit "0" }
func cocoaQuit(app) { msg_1(app, "terminate:", app)  emit "1" }

// ── Windows ────────────────────────────────────────────────────────────

func cocoaWindow(app, title, w, h) {
    let mask = 15                                 // Titled|Closable|Miniaturizable|Resizable
    let raw = msg(cls("NSWindow"), "alloc")
    let win = msg_rect(raw, "initWithContentRect:styleMask:backing:defer:",
        0, 0, w, h, mask, 2, 0)                   // backing = NSBackingStoreBuffered (2)
    msg_1(win, "setTitle:", nsString(title))
    emit win
}

func cocoaShow(win, app) { msg_1(win, "makeKeyAndOrderFront:", app)  emit "1" }
func cocoaTransparentTitlebar(win) { msg_1(win, "setTitlebarAppearsTransparent:", 1)  emit "1" }

// ── Widgets (attach to the window's content view) ───────────────────────

func cocoaButton(win, label, x, y, w, h) {
    let raw = msg(cls("NSButton"), "alloc")
    let btn = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(btn, "setTitle:", nsString(label))
    _addToContentView(win, btn)
    emit btn
}

func cocoaCheckbox(win, label, x, y, w, h) {
    let raw = msg(cls("NSButton"), "alloc")
    let cb = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(cb, "setTitle:", nsString(label))
    msg_1(cb, "setButtonType:", 3)        // NSButtonTypeSwitch
    _addToContentView(win, cb)
    emit cb
}

func cocoaTextField(win, x, y, w, h) {
    let raw = msg(cls("NSTextField"), "alloc")
    let tf = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(tf, "setEditable:", 1)
    msg_1(tf, "setSelectable:", 1)
    msg_1(tf, "setBezeled:", 1)            // visible, focusable input box
    msg_1(tf, "setDrawsBackground:", 1)
    _addToContentView(win, tf)
    emit tf
}

func cocoaSecureTextField(win, x, y, w, h) {
    let raw = msg(cls("NSSecureTextField"), "alloc")
    let tf = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(tf, "setEditable:", 1)
    msg_1(tf, "setSelectable:", 1)
    msg_1(tf, "setBezeled:", 1)
    msg_1(tf, "setDrawsBackground:", 1)
    _addToContentView(win, tf)
    emit tf
}

func cocoaLabel(win, text, x, y, w, h) {
    let raw = msg(cls("NSTextField"), "alloc")
    let lbl = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(lbl, "setStringValue:", nsString(text))
    msg_1(lbl, "setEditable:", 0)
    _addToContentView(win, lbl)
    emit lbl
}

func cocoaPlainLabel(win, text, x, y, w, h) {
    let raw = msg(cls("NSTextField"), "alloc")
    let lbl = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(lbl, "setStringValue:", nsString(text))
    msg_1(lbl, "setEditable:", 0)
    msg_1(lbl, "setSelectable:", 0)
    msg_1(lbl, "setBezeled:", 0)
    msg_1(lbl, "setBordered:", 0)
    msg_1(lbl, "setDrawsBackground:", 0)
    _addToContentView(win, lbl)
    emit lbl
}

func cocoaProgress(win, x, y, w, h) {
    let p = msg_frame(msg(cls("NSProgressIndicator"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(p, "setIndeterminate:", 0)
    msg_d1(p, "setMinValue:", 0)
    msg_d1(p, "setMaxValue:", 100)
    _addToContentView(win, p)
    emit p
}

func cocoaProgressSpinner(win, x, y, w, h) {
    let p = msg_frame(msg(cls("NSProgressIndicator"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(p, "setIndeterminate:", 1)
    msg_1(p, "setStyle:", 1)              // spinning
    _addToContentView(win, p)
    emit p
}

func cocoaSlider(win, x, y, w, h, min, max, value) {
    let s = msg_frame(msg(cls("NSSlider"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_d1(s, "setMinValue:", min)
    msg_d1(s, "setMaxValue:", max)
    msg_d1(s, "setDoubleValue:", value)
    _addToContentView(win, s)
    emit s
}

func cocoaComboBox(win, x, y, w, h) {
    let c = msg_frame(msg(cls("NSComboBox"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(c, "setEditable:", 1)
    msg_1(c, "setCompletes:", 1)
    _addToContentView(win, c)
    emit c
}

func cocoaSetText(control, text) { msg_1(control, "setStringValue:", nsString(text))  emit "1" }

func cocoaGetText(control) {
    let s = msg(control, "stringValue")
    emit msg(s, "UTF8String")
}

// ── Generic view/control state ────────────────────────────────────────
func cocoaSetEnabled(control, enabled) { msg_1(control, "setEnabled:", enabled)  emit "1" }
func cocoaSetHidden(view, hidden)      { msg_1(view, "setHidden:", hidden)       emit "1" }
func cocoaSetFrame(view, x, y, w, h)   { msg_frame(view, "setFrame:", x, y, w, h) emit "1" }
func cocoaSetTitle(obj, title)         { msg_1(obj, "setTitle:", nsString(title)) emit "1" }
func cocoaSetToolTip(view, text)       { msg_1(view, "setToolTip:", nsString(text)) emit "1" }
func cocoaSetEditable(control, editable) { msg_1(control, "setEditable:", editable) emit "1" }
func cocoaSetSelectable(control, selectable) { msg_1(control, "setSelectable:", selectable) emit "1" }
func cocoaSetBordered(control, bordered) { msg_1(control, "setBordered:", bordered) emit "1" }
func cocoaSetBezeled(control, bezeled) { msg_1(control, "setBezeled:", bezeled) emit "1" }
func cocoaSetDrawsBackground(control, draws) { msg_1(control, "setDrawsBackground:", draws) emit "1" }
func cocoaSetPlaceholder(control, text) { msg_1(control, "setPlaceholderString:", nsString(text)) emit "1" }
func cocoaSetAutoresizing(view, mask)  { msg_1(view, "setAutoresizingMask:", mask) emit "1" }
func cocoaRemove(view)                 { msg(view, "removeFromSuperview") emit "1" }
func cocoaSetWindowMinSize(win, w, h)  { msg_d2(win, "setMinSize:", w, h) emit "1" }
func cocoaState(control)               { emit msg(control, "state") }
func cocoaSetState(control, state)     { msg_1(control, "setState:", state) emit "1" }
func cocoaSetProgress(p, value)        { msg_d1(p, "setDoubleValue:", value) emit "1" }
func cocoaStartProgress(p)             { msg_1(p, "startAnimation:", p) emit "1" }
func cocoaStopProgress(p)              { msg_1(p, "stopAnimation:", p) emit "1" }
func cocoaComboAdd(combo, text)        { msg_1(combo, "addItemWithObjectValue:", nsString(text)) emit "1" }
func cocoaComboSelect(combo, index)    { msg_1(combo, "selectItemAtIndex:", index) emit "1" }
func cocoaComboSelected(combo)         { emit msg(combo, "indexOfSelectedItem") }
func cocoaComboSelectedText(combo) {
    let s = msg(combo, "objectValueOfSelectedItem")
    if s == 0 { emit "" }
    emit msg(s, "UTF8String")
}

func cocoaAlert(title, message) {
    let alert = allocInit("NSAlert")
    msg_1(alert, "setMessageText:", nsString(title))
    msg_1(alert, "setInformativeText:", nsString(message))
    msg(alert, "runModal")
    emit "1"
}

// ── Event handlers ─────────────────────────────────────────────────────
// The handler IS the Obj-C method IMP — objc passes (self, _cmd, sender) in
// x0/x1/x2 = Krypton's register calling convention, so a Krypton
// `func onClick(self, cmd, sender)` works directly. One synthesised target
// class per distinct handler (named from the funcptr).
// Wire a control to a handler, the synth class keyed by `keyName` (a funcptr
// is a raw pointer with NUL high bytes — "" + fnPtr collapses all handlers to
// one class; an explicit key keeps distinct handlers distinct). Many controls
// may share one keyName (= one class, the same handler) and read which one
// fired off `sender` via associated state.
func cocoaOnClickKeyed(control, keyName, fnPtr) {
    let nm = "KryptonObjkCB_" + _classSafe(keyName)
    let c = objc_lookUpClass(nm)
    if c == 0 {
        c = objc_allocateClassPair(cls("NSObject"), nm, 0)
        class_addMethod(c, sel("objk_dispatch:"), fnPtr, "v@:@")
        objc_registerClassPair(c)
    }
    let target = msg(msg(c, "alloc"), "init")
    msg_1(control, "setTarget:", target)
    msg_1(control, "setAction:", sel("objk_dispatch:"))
    emit "1"
}
func cocoaOnClick(control, fnPtr) { emit cocoaOnClickKeyed(control, "default", fnPtr) }

// ── Associated state (closure-capture equivalent) ──────────────────────
// Attach a value to a control; the handler reads it back off `sender`.
// sel("kr.assoc") is the key — sel_registerName is idempotent, so set + get
// resolve to the same stable SEL pointer (a plain string literal would be two
// different addresses and miss).
func cocoaSetAssoc(control, value) {
    objc_setAssociatedObject(control, sel("kr.assoc"), value, 1)  // RETAIN_NONATOMIC
    emit "1"
}

func cocoaGetAssoc(control) {
    emit objc_getAssociatedObject(control, sel("kr.assoc"))
}
// Keyed variants (attach several values under named keys; sel(key) is stable).
func cocoaSetAssocKey(control, key, value) { objc_setAssociatedObject(control, sel(key), value, 1)  emit "1" }
func cocoaGetAssocKey(control, key)        { emit objc_getAssociatedObject(control, sel(key)) }

// ── NSArray (mutable) — hold model data in Obj-C so stateless Krypton
//    delegates can read it back (no fork/exec inside AppKit callbacks) ────
func cocoaArray()             { emit msg(cls("NSMutableArray"), "array") }
func cocoaArrayAdd(arr, obj)  { msg_1(arr, "addObject:", obj)  emit "1" }
func cocoaArrayCount(arr)     { emit msg(arr, "count") }
func cocoaArrayGet(arr, i)    { emit msg_1(arr, "objectAtIndex:", i) }
func cocoaArraySet(arr, i, o) { msg_2(arr, "replaceObjectAtIndex:withObject:", i, o)  emit "1" }
func cocoaArrayRemove(arr, i) { msg_1(arr, "removeObjectAtIndex:", i)  emit "1" }
func cocoaNumber(n)           { emit msg_1(cls("NSNumber"), "numberWithInt:", n) }
func cocoaNumberVal(num)      { emit msg(num, "intValue") }

// ── Segmented control (tab bar) ────────────────────────────────────────
func cocoaSegmented(win, x, y, w, h) {
    let seg = msg_frame(msg(cls("NSSegmentedControl"), "alloc"), "initWithFrame:", x, y, w, h)
    _addToContentView(win, seg)
    emit seg
}
func cocoaSegCount(seg, n)        { msg_1(seg, "setSegmentCount:", n)  emit "1" }
func cocoaSegLabel(seg, lbl, i)   { msg_2(seg, "setLabel:forSegment:", nsString(lbl), i)  emit "1" }
func cocoaSegSelect(seg, i)       { msg_1(seg, "setSelectedSegment:", i)  emit "1" }
func cocoaSegSelected(seg)        { emit msg(seg, "selectedSegment") }
func cocoaSegOnChange(seg, fnPtr) { cocoaOnClick(seg, fnPtr)  emit "1" }

// ── Scrollable text view (the editor core kcode needs) ─────────────────
// NSTextView inside an NSScrollView. Returns the NSTextView handle; the
// scroll view is added to the window's content view. All plain msg/msg_frame
// — no new backend primitives needed.
func cocoaScrollText(win, x, y, w, h) {
    let sv = msg_frame(msg(cls("NSScrollView"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(sv, "setHasVerticalScroller:", 1)
    msg_1(sv, "setBorderType:", 2)                 // NSBezelBorder
    let tv = msg_frame(msg(cls("NSTextView"), "alloc"), "initWithFrame:", 0, 0, w, h)
    msg_1(tv, "setRichText:", 0)
    msg_1(sv, "setDocumentView:", tv)
    msg_1(sv, "setAutoresizingMask:", 18)   // width+height sizable -> follow the window
    _addToContentView(win, sv)
    emit tv
}
func cocoaTVSetString(tv, s) { msg_1(tv, "setString:", nsString(s))  emit "1" }
func cocoaTVGetString(tv)    { emit msg(msg(tv, "string"), "UTF8String") }
// Disable soft-wrap: the grid / source defines line breaks (terminal behaviour).
func cocoaTVNoWrap(tv) {
    let tc = msg(tv, "textContainer")
    msg_1(tc, "setWidthTracksTextView:", 0)
    msg_d2(tc, "setSize:", 1000000, 1000000)
    msg_1(tv, "setHorizontallyResizable:", 1)
    emit "1"
}
// Append without rebuilding the whole document (for streaming output, e.g. a pty).
func cocoaTVAppend(tv, s) {
    let astr = msg_1(msg(cls("NSAttributedString"), "alloc"), "initWithString:", nsString(s))
    msg_1(msg(tv, "textStorage"), "appendAttributedString:", astr)
    msg_1(tv, "scrollToEndOfDocument:", 0)
    emit "1"
}

// Syntax highlighting: colour a [loc, loc+len) range of the text view's storage.
// NSRange is a 16-byte struct (location, length) → passed as two GP args, so
// addAttribute:value:range: is a plain msg_4. Attribute keys use their stable
// runtime string values ("NSColor" = foreground, "NSFont" = font).
func cocoaTVColorRange(tv, color, loc, len) {
    let ts = msg(tv, "textStorage")
    let total = msg(ts, "length")
    if loc >= total { emit "1" }
    let l = len
    if loc + l > total { l = total - loc }
    msg_4(ts, "addAttribute:value:range:", nsString("NSColor"), color, loc, l)
    emit "1"
}
func cocoaTVFontRange(tv, font, loc, len) {
    let ts = msg(tv, "textStorage")
    let total = msg(ts, "length")
    if loc >= total { emit "1" }
    let l = len
    if loc + l > total { l = total - loc }
    msg_4(ts, "addAttribute:value:range:", nsString("NSFont"), font, loc, l)
    emit "1"
}
// Length of the text view's storage (for full-range ops).
func cocoaTVLength(tv) { emit msg(msg(tv, "textStorage"), "length") }

// ── Live syntax highlighting via the NSTextStorage delegate ────────────
// Set a delegate whose textStorageDidProcessEditing: (a Krypton func) re-colours
// on every edit — the canonical highlighting hook. These operate on the storage
// the delegate receives (notif object); guard on cocoaTSEditedChars so re-adding
// attributes (which itself fires the delegate) does not recurse.
func cocoaTVSetStorageDelegate(tv, d) { msg_1(msg(tv, "textStorage"), "setDelegate:", d)  emit "1" }
func cocoaTSString(ts)     { emit msg(msg(ts, "string"), "UTF8String") }
func cocoaTSLength(ts)     { emit msg(ts, "length") }
func cocoaTSEditedChars(ts){ emit bitAnd(msg(ts, "editedMask"), 2) }   // 2 = NSTextStorageEditedCharacters (1 = attributes)
func cocoaTSClearColor(ts) {
    msg_3(ts, "removeAttribute:range:", nsString("NSColor"), 0, msg(ts, "length"))
    emit "1"
}
func cocoaTSColorRange(ts, color, loc, len) {
    let total = msg(ts, "length")
    if loc >= total { emit "1" }
    let l = len
    if loc + l > total { l = total - loc }
    msg_4(ts, "addAttribute:value:range:", nsString("NSColor"), color, loc, l)
    emit "1"
}

// ── Colors (named — Krypton has no float literals for colorWithRed:…) ───
func cocoaColorNamed(name)        { emit msg(cls("NSColor"), name) }
func cocoaSystemWindowBg()        { emit cocoaColorNamed("windowBackgroundColor") }
func cocoaSystemText()            { emit cocoaColorNamed("textColor") }
func cocoaSystemSecondaryText()   { emit cocoaColorNamed("secondaryLabelColor") }
func cocoaSystemTextBg()          { emit cocoaColorNamed("textBackgroundColor") }
// True NSColor from 0-255 RGB (exact 256-colour/truecolor; named colours are the basic 16).
func cocoaRGB(r, g, b) { emit msg_rgb(cls("NSColor"), "colorWithRed:green:blue:alpha:", r, g, b) }
func cocoaSetBg(view, color)      { msg_1(view, "setBackgroundColor:", color)  emit "1" }
func cocoaSetTextColor(tv, color) { msg_1(tv, "setTextColor:", color)          emit "1" }
func cocoaSetWindowBg(win, color) { msg_1(win, "setBackgroundColor:", color)   emit "1" }

// ── Open panels ───────────────────────────────────────────────────────
func cocoaChooseFolder(title) {
    let panel = msg(cls("NSOpenPanel"), "openPanel")
    msg_1(panel, "setTitle:", nsString(title))
    msg_1(panel, "setCanChooseFiles:", 0)
    msg_1(panel, "setCanChooseDirectories:", 1)
    msg_1(panel, "setAllowsMultipleSelection:", 0)
    if msg(panel, "runModal") != 1 { emit "" }
    let url = msg(panel, "URL")
    if url == 0 { emit "" }
    emit msg(msg(url, "path"), "UTF8String")
}

func cocoaChooseFile(title) {
    let panel = msg(cls("NSOpenPanel"), "openPanel")
    msg_1(panel, "setTitle:", nsString(title))
    msg_1(panel, "setCanChooseFiles:", 1)
    msg_1(panel, "setCanChooseDirectories:", 0)
    msg_1(panel, "setAllowsMultipleSelection:", 0)
    if msg(panel, "runModal") != 1 { emit "" }
    let url = msg(panel, "URL")
    if url == 0 { emit "" }
    emit msg(msg(url, "path"), "UTF8String")
}

func cocoaSaveFile(title, defaultName) {
    let panel = msg(cls("NSSavePanel"), "savePanel")
    msg_1(panel, "setTitle:", nsString(title))
    if len(defaultName) > 0 { msg_1(panel, "setNameFieldStringValue:", nsString(defaultName)) }
    if msg(panel, "runModal") != 1 { emit "" }
    let url = msg(panel, "URL")
    if url == 0 { emit "" }
    emit msg(msg(url, "path"), "UTF8String")
}

// ── Pasteboard ────────────────────────────────────────────────────────
func cocoaClipboardText() {
    let pb = msg(cls("NSPasteboard"), "generalPasteboard")
    let s = msg_1(pb, "stringForType:", nsString("public.utf8-plain-text"))
    if s == 0 { emit "" }
    emit msg(s, "UTF8String")
}

func cocoaSetClipboardText(text) {
    let pb = msg(cls("NSPasteboard"), "generalPasteboard")
    msg(pb, "clearContents")
    msg_2(pb, "setString:forType:", nsString(text), nsString("public.utf8-plain-text"))
    emit "1"
}

// ── User defaults ─────────────────────────────────────────────────────
func cocoaDefaultsGet(key) {
    let s = msg_1(msg(cls("NSUserDefaults"), "standardUserDefaults"), "stringForKey:", nsString(key))
    if s == 0 { emit "" }
    emit msg(s, "UTF8String")
}

func cocoaDefaultsSet(key, value) {
    let d = msg(cls("NSUserDefaults"), "standardUserDefaults")
    msg_2(d, "setObject:forKey:", nsString(value), nsString(key))
    msg(d, "synchronize")
    emit "1"
}

func cocoaDefaultsRemove(key) {
    let d = msg(cls("NSUserDefaults"), "standardUserDefaults")
    msg_1(d, "removeObjectForKey:", nsString(key))
    msg(d, "synchronize")
    emit "1"
}

// ── Workspace / URL helpers ───────────────────────────────────────────
func cocoaURL(url)       { emit msg_1(cls("NSURL"), "URLWithString:", nsString(url)) }
func cocoaFileURL(path)  { emit msg_1(cls("NSURL"), "fileURLWithPath:", nsString(path)) }

func cocoaOpenURL(url) {
    let u = cocoaURL(url)
    if u == 0 { emit "0" }
    emit msg_1(msg(cls("NSWorkspace"), "sharedWorkspace"), "openURL:", u)
}

func cocoaOpenPath(path) {
    let u = cocoaFileURL(path)
    if u == 0 { emit "0" }
    emit msg_1(msg(cls("NSWorkspace"), "sharedWorkspace"), "openURL:", u)
}

func cocoaRevealPath(path) {
    let u = cocoaFileURL(path)
    if u == 0 { emit "0" }
    let arr = cocoaArray()
    cocoaArrayAdd(arr, u)
    msg_1(msg(cls("NSWorkspace"), "sharedWorkspace"), "activateFileViewerSelectingURLs:", arr)
    emit "1"
}

// ── Appearance helpers ────────────────────────────────────────────────
func cocoaAppearanceName(obj) {
    let a = msg(obj, "effectiveAppearance")
    if a == 0 { emit "" }
    let n = msg(a, "name")
    if n == 0 { emit "" }
    emit msg(n, "UTF8String")
}

func cocoaIsDark(obj) {
    if indexOf(cocoaAppearanceName(obj), "Dark") >= 0 { emit 1 }
    emit 0
}

func cocoaSetAppearance(obj, name) {
    let a = msg_1(cls("NSAppearance"), "appearanceNamed:", nsString(name))
    if a == 0 { emit "0" }
    msg_1(obj, "setAppearance:", a)
    emit "1"
}

// ── Fonts ──────────────────────────────────────────────────────────────
// [NSFont userFixedPitchFontOfSize:n] — monospaced (size in pt, int is fine).
func cocoaMonoFont(size)     { emit msg_d1(cls("NSFont"), "userFixedPitchFontOfSize:", size) }
// Refamily a font (keeps size/metrics) — e.g. to a Nerd Font for powerline glyphs.
// Returns `base` unchanged if the family isn't installed. No double arg needed.
func cocoaFontFamily(base, family) {
    emit msg_2(msg(cls("NSFontManager"), "sharedFontManager"), "convertFont:toFamily:", base, nsString(family))
}
func cocoaSetFont(view, font){ msg_1(view, "setFont:", font)  emit "1" }

// ── Runtime class synthesis (delegates / data sources) ─────────────────
// Build an Obj-C class at runtime whose methods are Krypton funcs (used as
// IMPs). Lets a data source / delegate be written in pure Krypton — every
// method takes (self, _cmd, …) and returns via x0/d0.
//   let c = cocoaClassNew("MyDataSource")
//   cocoaClassAddMethod(c, "numberOfRowsInTableView:", funcptr(nrows), "q@:@")
//   cocoaClassRegister(c)
//   let inst = cocoaNew(c)
func cocoaClassNew(name)            { emit objc_allocateClassPair(cls("NSObject"), name, 0) }
// Subclass NSView (for a custom-drawn view: add a drawRect: method whose IMP is a
// Krypton func). The drawRect: dirtyRect arrives in d0..d3 (FP regs) and is simply
// ignored by the Krypton handler (it reads x0=self, x1=_cmd).
func cocoaViewClassNew(name)        { emit objc_allocateClassPair(cls("NSView"), name, 0) }
// Fill the current colour into a rect (call [color set] first). NSBezierPath fillRect:
// takes only the NSRect -> d0..d3, so it's msg_frame.
func cocoaFillRect(x, y, w, h)      { msg_frame(cls("NSBezierPath"), "fillRect:", x, y, w, h)  emit "1" }
func cocoaColorSet(color)           { msg(color, "set")  emit "1" }
// Build a text-attributes dict {font, color} for drawing strings.
func cocoaTextAttrs(font, color) {
    let d = msg(cls("NSMutableDictionary"), "dictionary")
    msg_2(d, "setObject:forKey:", font, nsString("NSFont"))
    msg_2(d, "setObject:forKey:", color, nsString("NSColor"))
    emit d
}
func cocoaSetButtonTextColor(btn, color) {
    let title = msg(btn, "title")
    let attrs = cocoaTextAttrs(msg(btn, "font"), color)
    let astr = msg_2(msg(cls("NSAttributedString"), "alloc"), "initWithString:attributes:", title, attrs)
    msg_1(btn, "setAttributedTitle:", astr)
    emit "1"
}
// Draw a string into a rect with the given attributes (use inside drawRect:).
func cocoaDrawText(str, x, y, w, h, attrs) {
    msg_rectp(nsString(str), "drawInRect:withAttributes:", x, y, w, h, attrs)
    emit "1"
}
// Instantiate a custom view with a frame and add it to the window.
func cocoaCustomView(win, c, x, y, w, h) {
    let v = msg_frame(msg(c, "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(v, "setAutoresizingMask:", 18)   // width+height sizable -> follow the window
    _addToContentView(win, v)
    emit v
}
func cocoaNeedsDisplay(v)           { msg_1(v, "setNeedsDisplay:", 1)  emit "1" }
func cocoaMakeFirstResponder(win, v){ msg_1(win, "makeFirstResponder:", v)  emit "1" }

// ── Timer (repeating) — drives async work (e.g. polling a pty) ─────────
// Fires `actionSel` on `target` every `ms` milliseconds (ms/1000 -> TimeInterval).
func cocoaTimer(target, actionSel, ms) {
    emit msg_timer(cls("NSTimer"), "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:",
        ms, target, actionSel, 0, 1)
}

// ── Manual event loop ──────────────────────────────────────────────────
// Use instead of cocoaRun when you must interleave native work (e.g. reading a
// pty) with event handling in the MAIN flow — doing such work inside a timer/
// action callback can fault. cocoaFinishLaunching once, then loop:
//   cocoaPumpEvents(app)  // drain pending events
//   <your work>
//   sleepUs(0, 8000)
func cocoaFinishLaunching(app) { msg(app, "finishLaunching")  msg_1(app, "activateIgnoringOtherApps:", 1)  emit "1" }
// Dispatch one pending event (non-blocking); returns 1 if one was handled, else 0.
func cocoaPumpEvent(app) {
    let ev = msg_4(app, "nextEventMatchingMask:untilDate:inMode:dequeue:",
        0 - 1, 0, nsString("kCFRunLoopDefaultMode"), 1)
    if ev == 0 { emit 0 }
    // key-down with a modifier: let the main menu claim ⌘-shortcuts first
    // ([NSApp run] does this automatically; the manual pump must do it itself).
    if msg(ev, "type") == 10 {
        let mm = msg(app, "mainMenu")
        if mm != 0 { if msg_1(mm, "performKeyEquivalent:", ev) == 1 { emit 1 } }
    }
    msg_1(app, "sendEvent:", ev)
    emit 1
}
// Drain all currently-pending events.
func cocoaPumpEvents(app) {
    while cocoaPumpEvent(app) == 1 { }
    emit "1"
}
func cocoaClassAddMethod(c, selName, fnPtr, types) { class_addMethod(c, sel(selName), fnPtr, types)  emit "1" }
func cocoaClassRegister(c)          { objc_registerClassPair(c)  emit "1" }
func cocoaNew(c)                    { emit msg(msg(c, "alloc"), "init") }

// ── Table view (single column) — feed it a data source instance ────────
func cocoaTable(win, x, y, w, h) {
    let sv = msg_frame(msg(cls("NSScrollView"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(sv, "setHasVerticalScroller:", 1)
    msg_1(sv, "setBorderType:", 0)             // no bezel border
    msg_1(sv, "setFocusRingType:", 1)          // no blue focus ring
    let tbl = msg_frame(msg(cls("NSTableView"), "alloc"), "initWithFrame:", 0, 0, w, h)
    msg_1(tbl, "setFocusRingType:", 1)
    let col = msg_1(msg(cls("NSTableColumn"), "alloc"), "initWithIdentifier:", nsString("c0"))
    msg_d1(col, "setWidth:", w)
    msg_1(tbl, "addTableColumn:", col)
    msg_1(sv, "setDocumentView:", tbl)
    _addToContentView(win, sv)
    emit tbl
}
func cocoaSetDataSource(table, ds) { msg_1(table, "setDataSource:", ds)  emit "1" }
func cocoaReload(table)            { msg(table, "reloadData")            emit "1" }

// ── Split view (sidebar | main — kcode's layout) ───────────────────────
func cocoaSplit(win, x, y, w, h) {
    let sp = msg_frame(msg(cls("NSSplitView"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(sp, "setVertical:", 1)
    _addToContentView(win, sp)
    emit sp
}
func cocoaSplitAdd(split, view) { msg_1(split, "addSubview:", view)  emit "1" }

// ── Menu bar ───────────────────────────────────────────────────────────
func cocoaMenuBar(app) {
    let bar = msg(cls("NSMenu"), "new")
    msg_1(app, "setMainMenu:", bar)
    emit bar
}
// Add a top-level menu (e.g. the app menu) to the bar; returns the submenu so
// items can be added to it.
func cocoaMenuAdd(bar, title) {
    let item = msg_3(msg(cls("NSMenuItem"), "alloc"), "initWithTitle:action:keyEquivalent:",
        nsString(title), 0, nsString(""))
    let sub = msg_1(msg(cls("NSMenu"), "alloc"), "initWithTitle:", nsString(title))
    msg_1(item, "setSubmenu:", sub)
    msg_1(bar, "addItem:", item)
    emit sub
}
// Add a menu item bound to a built-in selector with NO target — it dispatches up
// the responder chain to the first responder (e.g. cut:/copy:/paste:/selectAll:/
// performFindPanelAction: handled by the focused NSTextView). Standard editing.
func cocoaMenuItemSel(menu, title, key, selName) {
    let item = msg_3(msg(cls("NSMenuItem"), "alloc"), "initWithTitle:action:keyEquivalent:",
        nsString(title), sel(selName), nsString(key))
    msg_1(menu, "addItem:", item)
    emit "1"
}
// A separator line in a menu.
func cocoaMenuSeparator(menu) { msg_1(menu, "addItem:", msg(cls("NSMenuItem"), "separatorItem"))  emit "1" }
// Selector-action item carrying a tag (e.g. performTextFinderAction: reads sender.tag).
func cocoaMenuItemSelTag(menu, title, key, selName, tag) {
    let item = msg_3(msg(cls("NSMenuItem"), "alloc"), "initWithTitle:action:keyEquivalent:",
        nsString(title), sel(selName), nsString(key))
    msg_1(item, "setTag:", tag)
    msg_1(menu, "addItem:", item)
    emit "1"
}
// A submenu inside `menu` — returns the submenu to add items to.
func cocoaSubmenuIn(menu, title) {
    let item = msg_3(msg(cls("NSMenuItem"), "alloc"), "initWithTitle:action:keyEquivalent:",
        nsString(title), 0, nsString(""))
    let sub = msg_1(msg(cls("NSMenu"), "alloc"), "initWithTitle:", nsString(title))
    msg_1(item, "setSubmenu:", sub)
    msg_1(menu, "addItem:", item)
    emit sub
}
// objc-class-name-safe form of a string (alnum kept, rest -> '_').
func _classSafe(s) {
    let out = ""
    let n = len(s)
    let i = 0
    while i < n {
        let c = charCode(substring(s, i, i + 1))
        if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { out = out + substring(s, i, i + 1) }
        else { out = out + "_" }
        i = i + 1
    }
    emit out
}
// Add an action item to a menu, wired to a Krypton handler.
func cocoaMenuItem(menu, title, key, fnPtr) {
    // Key the synth class by title, NOT ("" + fnPtr): a funcptr is a raw
    // pointer whose high bytes are NUL, so "" + fnPtr truncates to the SAME
    // string for every handler -> all items collapse onto one class and fire
    // the first handler. Title-keying gives each item its own class + IMP.
    let nm = "KryptonObjkMenuCB_" + _classSafe(title) + "_" + len(title)
    let c = objc_lookUpClass(nm)
    if c == 0 {
        c = objc_allocateClassPair(cls("NSObject"), nm, 0)
        class_addMethod(c, sel("objk_dispatch:"), fnPtr, "v@:@")
        objc_registerClassPair(c)
    }
    let target = msg(msg(c, "alloc"), "init")
    let item = msg_3(msg(cls("NSMenuItem"), "alloc"), "initWithTitle:action:keyEquivalent:",
        nsString(title), sel("objk_dispatch:"), nsString(key))
    msg_1(item, "setTarget:", target)
    msg_1(menu, "addItem:", item)
    emit "1"
}

// ── Internal helpers ───────────────────────────────────────────────────

func _addToContentView(win, view) {
    let cv = msg(win, "contentView")
    msg_1(cv, "addSubview:", view)
}
