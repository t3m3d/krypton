#!/usr/bin/env kr
// examples/cocoa_hello.ks — Minimal Cocoa app written in pure Krypton.
//
// Native macOS arm64 window with a label and a button. Click the button,
// the label updates. ~30 lines of Krypton, no Swift / Obj-C source files.
//
// Build + run (macOS arm64):
//   kr cocoa_hello.ks                  # or: kcc -r cocoa_hello.ks
//
// State pattern: `stdlib/cocoa.k` is fully stateless, so the caller
// holds every handle (app, win, label, etc.) explicitly. The click
// handler receives `sender` and uses `cocoaSenderTag` to look up its
// own associated state — same approach as Swift's @objc actions, just
// with explicit `funcptr` registration instead of compiler-synthesized
// selectors.
//
// SCAFFOLD — runs on macOS arm64 once agent m lands the macho codegen
// for objc_msgSend + NSRect ABI + the KrCallbackTarget trampoline.
// Until then this file parses + the symbols resolve at link, but
// clicks don't fire.

// Krypton imports are NOT transitive — pull in every layer explicitly.
import "k:cocoa"
import "k:objc"
import "head:cocoa"
import "head:objc"

// Click handler. Receives the sender (the NSButton instance). We use
// envGet on a shared GC env that the main flow attaches to the button
// via cocoaSetAssoc — that's the Cocoa-idiomatic equivalent of a
// closure capture. (envs survive across calls because they're GC heap
// objects, unlike module-level `let` which doesn't init on import.)
// objk: an action handler IS the Obj-C method IMP, so it takes the full
// (self, _cmd, sender) the runtime passes. `sender` is the clicked control.
// The label was attached to the button via cocoaSetAssoc, so the handler
// pulls it back off `sender` and updates it — pure-Krypton closure capture.
func onClick(self, cmd, sender) {
    let lbl = cocoaGetAssoc(sender)
    cocoaSetText(lbl, "Clicked! (from a pure-Krypton handler)")
}

just run {
    let app = cocoaInit()
    let win = cocoaWindow(app, "Hello, KryptScript", 400, 200)

    let lbl = cocoaLabel(win, "Click the button.", 40, 110, 320, 24)
    let btn = cocoaButton(win, "Click me", 150, 50, 100, 32)

    // Attach the label to the button so onClick can find it via the sender.
    cocoaSetAssoc(btn, lbl)

    cocoaOnClick(btn, funcptr(onClick))
    cocoaShow(win, app)
    cocoaRun(app)
}
