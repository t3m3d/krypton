// stdlib/cocoa.k — High-level Cocoa GUI for macOS, written in Krypton.
//
// The "Swift-equivalent" surface: short, idiomatic helpers for the
// minimum useful set of AppKit widgets — application, window, button,
// label, text field, alert. Same role as stdlib/gui.k on Windows.
//
// Example (see also examples/cocoa_hello.ks):
//
//   import "k:cocoa"
//
//   func onHello() {
//       cocoaAlert("Hello", "From pure Krypton!")
//   }
//
//   just run {
//       cocoaInit()
//       let win = cocoaWindow("Demo", 400, 220)
//       let btn = cocoaButton(win, "Click me", 150, 90, 100, 30)
//       cocoaOnClick(btn, funcptr(onHello))
//       cocoaRun()
//   }
//
// Pure Krypton on top of stdlib/objc.k. No Obj-C source files anywhere
// in the project — every API below is just `msg(...)` calls into the
// Cocoa runtime.
//
// SCAFFOLD — agent m owns the macho_arm64_self.k codegen plumbing for
// objc_msgSend on arm64 (self in x0, sel in x1, args in x2..x7) and the
// JS↔WASM-style callback bridge required for cocoaOnClick handlers.
// Once that lands, this stdlib should run as-is on macOS arm64.

module cocoa

import "k:objc"
import "head:cocoa"

// Module-global handle to the shared NSApplication. cocoaInit sets it
// once; subsequent calls reuse it. Stored via guiStateSet-equivalent
// pattern would be cleaner — for now a plain `let` (mutable module
// global) keeps the surface small. KNOWN BUG with mutable module
// globals on the native pipeline; if hit, port to env-based storage.
let _cocoa_app = ""

// ── App lifecycle ──────────────────────────────────────────────────────

// Initialise the shared NSApplication and request a regular-mode
// activation policy (gets a Dock icon, a menu bar, the works). Call
// once at process startup before any window creation.
func cocoaInit() {
    let app = msg(cls(NSApplication_cls), sel_sharedApplication)
    msg_1(app, sel_setActivationPolicy, NSApplicationActivationPolicyRegular)
    msg_1(app, sel_activateIgnoringOtherApps, "1")
    _cocoa_app = app
    emit "1"
}

// Block running the AppKit event loop. Returns when the user quits via
// the standard Cmd+Q / app menu Quit item. Equivalent of Windows
// guiRun().
func cocoaRun() {
    msg(_cocoa_app, sel_run)
    emit "0"
}

// Quit the running app. Posts the standard terminate: message to the
// shared NSApplication, draining the event loop.
func cocoaQuit() {
    msg_1(_cocoa_app, sel_terminate, _cocoa_app)
    emit "1"
}

// ── Windows ────────────────────────────────────────────────────────────

// Create a top-level window (titled, closable, miniaturisable, resizable)
// of the given content size. Returns the NSWindow handle. The window is
// hidden until you call cocoaShow().
func cocoaWindow(title, w, h) {
    let mask = NSWindowStyleMaskTitled +
               NSWindowStyleMaskClosable +
               NSWindowStyleMaskMiniaturizable +
               NSWindowStyleMaskResizable
    let raw = msg(cls(NSWindow_cls), sel_alloc)
    // Rect is passed as (x, y, w, h) double-quad. The codegen pushes
    // it as a struct argument — agent m's macho backend has to handle
    // the NSRect ABI specifically for this call. See docs/cocoa_design.md.
    let win = msg_4(raw,
        sel_initWithContentRect_styleMask_backing_defer,
        _ns_rect(0, 0, w, h),
        mask, NSBackingStoreBuffered, "0")
    msg_1(win, sel_setTitle, nsString(title))
    emit win
}

// Show + activate the window.
func cocoaShow(win) {
    msg_1(win, sel_makeKeyAndOrderFront, _cocoa_app)
    emit "1"
}

// ── Widgets (all attach to the window's content view) ──────────────────

// Push-button. `target`/`action` are wired via cocoaOnClick after
// creation — the alloc/init is done here so the user gets a handle they
// can stash.
func cocoaButton(win, label, x, y, w, h) {
    let raw = msg(cls(NSButton_cls), sel_alloc)
    let btn = msg_1(raw, sel_initWithFrame, _ns_rect(x, y, w, h))
    msg_1(btn, sel_setTitle, nsString(label))
    _addToContentView(win, btn)
    emit btn
}

// Editable single-line text field.
func cocoaTextField(win, x, y, w, h) {
    let raw = msg(cls(NSTextField_cls), sel_alloc)
    let tf = msg_1(raw, sel_initWithFrame, _ns_rect(x, y, w, h))
    msg_1(tf, sel_setEditable, "1")
    _addToContentView(win, tf)
    emit tf
}

// Static text label (NSTextField with editable=false).
func cocoaLabel(win, text, x, y, w, h) {
    let raw = msg(cls(NSTextField_cls), sel_alloc)
    let lbl = msg_1(raw, sel_initWithFrame, _ns_rect(x, y, w, h))
    msg_1(lbl, sel_setStringValue, nsString(text))
    msg_1(lbl, sel_setEditable, "0")
    _addToContentView(win, lbl)
    emit lbl
}

// Modal alert dialog. Blocks until the user dismisses it.
func cocoaAlert(title, message) {
    let alert = allocInit(NSAlert_cls)
    msg_1(alert, sel_setMessageText, nsString(title))
    msg_1(alert, sel_setInformativeText, nsString(message))
    msg(alert, sel_runModal)
    emit "1"
}

// ── Event handlers ─────────────────────────────────────────────────────

// Wire a Krypton funcptr to a button's click action. THE HARDEST PIECE:
// Cocoa wants a target/action pair where target is an Obj-C object and
// action is a selector ON that object. We can't hand it a raw Krypton
// function pointer directly.
//
// Solution: register the funcptr in a global table, then create a tiny
// Obj-C trampoline object (subclassed from NSObject at runtime via
// objc_allocateClassPair / class_addMethod) whose action dispatches
// into our table by index.
//
// This stub records the binding; the actual trampoline + dispatch is
// installed by agent m's codegen-side work. See docs/cocoa_design.md
// section "Callback bridge".
let _cocoa_callbacks = ""
func cocoaOnClick(btn, fnPtr) {
    let id = _next_callback_id()
    _cocoa_callbacks = _cocoa_callbacks + id + "=" + fnPtr + ","
    // Until the trampoline lands, this is a no-op binding — clicks
    // simply have no effect. Programs still link and run.
    emit "1"
}

let _cocoa_cb_counter = 0
func _next_callback_id() {
    _cocoa_cb_counter = _cocoa_cb_counter + 1
    emit "kbcb_" + _cocoa_cb_counter
}

// ── Internal helpers ───────────────────────────────────────────────────

func _addToContentView(win, view) {
    let cv = msg(win, sel_contentView)
    msg_1(cv, sel_addSubview, view)
}

// NSRect is a struct of 4 CGFloats {x, y, w, h}. The codegen
// represents it as a packed 4-double pseudo-handle that the macho
// backend unpacks back into the right registers for the call. Inline
// here so the IR walker sees a single primitive.
func _ns_rect(x, y, w, h) {
    emit x + "," + y + "," + w + "," + h
}
