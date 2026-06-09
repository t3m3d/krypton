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
//   import "k:objc"          // imports are NOT transitive — pull both in
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

// ── Widgets (attach to the window's content view) ───────────────────────

func cocoaButton(win, label, x, y, w, h) {
    let raw = msg(cls("NSButton"), "alloc")
    let btn = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(btn, "setTitle:", nsString(label))
    _addToContentView(win, btn)
    emit btn
}

func cocoaTextField(win, x, y, w, h) {
    let raw = msg(cls("NSTextField"), "alloc")
    let tf = msg_frame(raw, "initWithFrame:", x, y, w, h)
    msg_1(tf, "setEditable:", 1)
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

func cocoaSetText(control, text) { msg_1(control, "setStringValue:", nsString(text))  emit "1" }

func cocoaGetText(control) {
    let s = msg(control, "stringValue")
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
func cocoaOnClick(control, fnPtr) {
    let nm = "KryptonObjkCB" + ("" + fnPtr)
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
    _addToContentView(win, sv)
    emit tv
}
func cocoaTVSetString(tv, s) { msg_1(tv, "setString:", nsString(s))  emit "1" }
func cocoaTVGetString(tv)    { emit msg(msg(tv, "string"), "UTF8String") }

// Syntax highlighting: colour a [loc, loc+len) range of the text view's storage.
// NSRange is a 16-byte struct (location, length) → passed as two GP args, so
// addAttribute:value:range: is a plain msg_4. Attribute keys use their stable
// runtime string values ("NSColor" = foreground, "NSFont" = font).
func cocoaTVColorRange(tv, color, loc, len) {
    let ts = msg(tv, "textStorage")
    msg_4(ts, "addAttribute:value:range:", nsString("NSColor"), color, loc, len)
    emit "1"
}
func cocoaTVFontRange(tv, font, loc, len) {
    let ts = msg(tv, "textStorage")
    msg_4(ts, "addAttribute:value:range:", nsString("NSFont"), font, loc, len)
    emit "1"
}
// Length of the text view's storage (for full-range ops).
func cocoaTVLength(tv) { emit msg(msg(tv, "textStorage"), "length") }

// ── Colors (named — Krypton has no float literals for colorWithRed:…) ───
func cocoaColorNamed(name)        { emit msg(cls("NSColor"), name) }
func cocoaSetBg(view, color)      { msg_1(view, "setBackgroundColor:", color)  emit "1" }
func cocoaSetTextColor(tv, color) { msg_1(tv, "setTextColor:", color)          emit "1" }

// ── Fonts ──────────────────────────────────────────────────────────────
// [NSFont userFixedPitchFontOfSize:n] — monospaced (size in pt, int is fine).
func cocoaMonoFont(size)     { emit msg_d1(cls("NSFont"), "userFixedPitchFontOfSize:", size) }
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
// Instantiate a custom view with a frame and add it to the window.
func cocoaCustomView(win, c, x, y, w, h) {
    let v = msg_frame(msg(c, "alloc"), "initWithFrame:", x, y, w, h)
    _addToContentView(win, v)
    emit v
}
func cocoaNeedsDisplay(v)           { msg_1(v, "setNeedsDisplay:", 1)  emit "1" }
func cocoaClassAddMethod(c, selName, fnPtr, types) { class_addMethod(c, sel(selName), fnPtr, types)  emit "1" }
func cocoaClassRegister(c)          { objc_registerClassPair(c)  emit "1" }
func cocoaNew(c)                    { emit msg(msg(c, "alloc"), "init") }

// ── Table view (single column) — feed it a data source instance ────────
func cocoaTable(win, x, y, w, h) {
    let sv = msg_frame(msg(cls("NSScrollView"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(sv, "setHasVerticalScroller:", 1)
    msg_1(sv, "setBorderType:", 2)
    let tbl = msg_frame(msg(cls("NSTableView"), "alloc"), "initWithFrame:", 0, 0, w, h)
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
// Add an action item to a menu, wired to a Krypton handler (one class per fn).
func cocoaMenuItem(menu, title, key, fnPtr) {
    let nm = "KryptonObjkMenuCB" + ("" + fnPtr)
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
