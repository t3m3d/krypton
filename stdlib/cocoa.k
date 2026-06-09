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

// ── Internal helpers ───────────────────────────────────────────────────

func _addToContentView(win, view) {
    let cv = msg(win, "contentView")
    msg_1(cv, "addSubview:", view)
}
