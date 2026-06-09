// stdlib/cocoa.k — High-level Cocoa GUI for macOS, written in Krypton.
//
// The "Swift-equivalent" surface — short, idiomatic helpers for the
// minimum useful set of AppKit widgets. Same role as `stdlib/gui.k` on
// Windows, same caller-threads-state convention as `stdlib/server_native.k`.
//
// Example (see also examples/cocoa_hello.ks):
//
//   import "k:cocoa"
//
//   func onHello(sender) {
//       cocoaAlert("Hello", "From pure Krypton!")
//   }
//
//   just run {
//       let app = cocoaInit()
//       let win = cocoaWindow(app, "Demo", 400, 220)
//       let btn = cocoaButton(win, "Click me", 150, 90, 100, 30)
//       cocoaOnClick(btn, funcptr(onHello))
//       cocoaShow(win, app)
//       cocoaRun(app)
//   }
//
// FULLY STATELESS module — no `let` outside function bodies. Every
// public function takes the relevant handle(s) and returns new ones.
// Caller is responsible for holding them. This matches the explicit-
// state pattern agent m shipped in `stdlib/server_native.k` after
// confirming module-level mutable state doesn't survive the import
// boundary on the native pipeline.
//
// SCAFFOLD — agent m owns the macho_arm64_self.k codegen plumbing for
// objc_msgSend (self in x0, sel in x1, args in x2..x7 on arm64) and
// the Obj-C trampoline class used by cocoaOnClick. Once both land,
// this stdlib is fully runnable on macOS arm64.

module cocoa

import "k:objc"
import "head:cocoa"

// ── App lifecycle ──────────────────────────────────────────────────────

// cocoaInit() — set up the NSApplication, request a regular-mode
// activation policy (Dock icon, menu bar, focus), and return the app
// handle. Call once at process start. Pass the returned handle to
// cocoaShow / cocoaRun / cocoaQuit.
func cocoaInit() {
    let app = msg(cls(NSApplication_cls), sel_sharedApplication)
    msg_1(app, sel_setActivationPolicy, NSApplicationActivationPolicyRegular)
    msg_1(app, sel_activateIgnoringOtherApps, "1")
    emit app
}

// Block running the AppKit event loop until the user quits. Equivalent
// of Windows guiRun().
func cocoaRun(app) {
    msg(app, sel_run)
    emit "0"
}

// Quit the running app. Posts `terminate:` to the shared NSApplication
// to drain the event loop.
func cocoaQuit(app) {
    msg_1(app, sel_terminate, app)
    emit "1"
}

// ── Windows ────────────────────────────────────────────────────────────

// Create a top-level window with the standard four buttons (titled,
// closable, miniaturisable, resizable). Returns the NSWindow handle.
// Pass it to cocoaShow with the app handle to make it visible.
func cocoaWindow(app, title, w, h) {
    let mask = NSWindowStyleMaskTitled +
               NSWindowStyleMaskClosable +
               NSWindowStyleMaskMiniaturizable +
               NSWindowStyleMaskResizable
    let raw = msg(cls(NSWindow_cls), sel_alloc)
    let win = msg_rect(raw, sel_initWithContentRect_styleMask_backing_defer,
        0, 0, w, h, mask, NSBackingStoreBuffered, 0)
    msg_1(win, sel_setTitle, nsString(title))
    emit win
}

// Show + activate the window. Needs the app handle to receive the
// makeKeyAndOrderFront: sender argument.
func cocoaShow(win, app) {
    msg_1(win, sel_makeKeyAndOrderFront, app)
    emit "1"
}

// ── Widgets ────────────────────────────────────────────────────────────
// All attach to the window's content view (Cocoa convention).

func cocoaButton(win, label, x, y, w, h) {
    let raw = msg(cls(NSButton_cls), sel_alloc)
    let btn = msg_frame(raw, sel_initWithFrame, x, y, w, h)
    msg_1(btn, sel_setTitle, nsString(label))
    _addToContentView(win, btn)
    emit btn
}

func cocoaTextField(win, x, y, w, h) {
    let raw = msg(cls(NSTextField_cls), sel_alloc)
    let tf = msg_frame(raw, sel_initWithFrame, x, y, w, h)
    msg_1(tf, sel_setEditable, "1")
    _addToContentView(win, tf)
    emit tf
}

func cocoaLabel(win, text, x, y, w, h) {
    let raw = msg(cls(NSTextField_cls), sel_alloc)
    let lbl = msg_frame(raw, sel_initWithFrame, x, y, w, h)
    msg_1(lbl, sel_setStringValue, nsString(text))
    msg_1(lbl, sel_setEditable, "0")
    _addToContentView(win, lbl)
    emit lbl
}

// Update the text on any NSControl that has a stringValue (labels,
// text fields, buttons). The handle is whatever cocoaLabel / cocoaButton
// / cocoaTextField returned.
func cocoaSetText(control, text) {
    msg_1(control, sel_setStringValue, nsString(text))
    emit "1"
}

// Read the current text from an editable NSTextField. Returns a
// Krypton string (NSString → UTF8String).
func cocoaGetText(control) {
    let nsstr = msg(control, sel_stringValue)
    emit msg(nsstr, sel_UTF8String)
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

// Wire a Krypton funcptr to a control's primary action (the click
// event for buttons, the return-key event for text fields).
//
// Implementation contract (agent m owns the macho-side machine code):
//
//   1. The macho backend emits a built-in Obj-C class named
//      `KrCallbackTarget` once per process at startup. The class has
//      a single method `krDispatch:` whose implementation calls back
//      into a Krypton-level dispatcher.
//   2. cocoaOnClick(control, fnPtr) sets the control's target to a
//      fresh KrCallbackTarget instance whose `krDispatch:` is wired
//      to the user's fnPtr. The standard Obj-C pattern uses
//      `objc_setAssociatedObject` to attach the fnPtr directly to the
//      target instance — when AppKit fires the action, the trampoline
//      pulls the fnPtr off `self` and invokes it.
//   3. The dispatcher in Krypton receives (sender) as its sole arg
//      and is a regular Krypton func — so user handlers look like:
//
//          func onSave(sender) { ... }
//
// Until that pipeline lands the call is a no-op binding (programs
// still link and run, clicks have no effect).
// Implemented via objk (2026-06-09): the handler IS the Obj-C method IMP — objc
// passes (self, _cmd, sender) in x0/x1/x2, which is exactly Krypton's register
// calling convention, so a Krypton `func onClick(self, cmd, sender)` works directly.
// We synthesise one target class per distinct handler (named from the funcptr),
// add `objk_dispatch:` with the handler as its IMP, and point the control's
// target/action at it. Handlers take (self, cmd, sender) — use `sender` for the
// control and cocoaGetAssoc(sender) for attached state.
func cocoaOnClick(control, fnPtr) {
    let nm = "KryptonObjkCB" + ("" + fnPtr)
    let c = objc_lookUpClass(nm)
    if c == 0 {
        c = objc_allocateClassPair(cls(NSObject_cls), nm, 0)
        class_addMethod(c, sel("objk_dispatch:"), fnPtr, "v@:@")
        objc_registerClassPair(c)
    }
    let target = msg(msg(c, sel_alloc), sel_init)
    msg_1(control, "setTarget:", target)
    msg_1(control, "setAction:", sel("objk_dispatch:"))
    emit "1"
}

// ── Associated state (closure-capture equivalent) ──────────────────────
// Krypton has closures, but they can't be passed as raw funcptrs into
// the Obj-C target/action ABI — Obj-C only knows about (target, sel)
// pairs. So we use the standard Obj-C escape hatch: attach a per-
// instance value to the control via objc_setAssociatedObject. The
// trampoline reads it back via objc_getAssociatedObject and hands it
// to the user's Krypton handler as a sidecar argument.
//
// Use `envNew()` / `envSet(env, k, v)` / `envGet(env, k)` to bundle
// multiple state slots into the single associated object.
//
// _ASSOC_KEY is any unique pointer; we pick a fixed sentinel string so
// every cocoaSetAssoc / cocoaGetAssoc pair sees the same identity.
const _ASSOC_KEY = "kr.assoc"
// OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1.
const _ASSOC_POLICY_RETAIN = 1

func cocoaSetAssoc(control, value) {
    objc_setAssociatedObject(control, _ASSOC_KEY, value, _ASSOC_POLICY_RETAIN)
    emit "1"
}

func cocoaGetAssoc(control) {
    emit objc_getAssociatedObject(control, _ASSOC_KEY)
}

// ── Internal helpers ───────────────────────────────────────────────────

func _addToContentView(win, view) {
    let cv = msg(win, sel_contentView)
    msg_1(cv, sel_addSubview, view)
}

// NSRect is a struct of 4 CGFloats {x, y, w, h}. The codegen
// represents it as a packed 4-double pseudo-handle the macho backend
// unpacks into d0..d3 for the initWithContentRect:/initWithFrame:
// calls. Inline so the IR walker sees a single primitive.
func _nsRect(x, y, w, h) {
    emit x + "," + y + "," + w + "," + h
}
