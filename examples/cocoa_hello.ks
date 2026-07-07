#!/usr/bin/env kr
// examples/cocoa_hello.ks — Minimal Cocoa app written in pure Krypton.
//
// Native macOS arm64 window with a label and a button. Click the button,
// the label updates. ~30 lines of Krypton, no Swift / Obj-C source files.
//
// Build + run (macOS arm64) — use the REPO native pipeline, not a stale
// Homebrew `kcc` (releases before the objk foreign-import work silently
// produce broken objc binaries — SIGILL at launch):
//   ./build.sh run examples/cocoa_hello.ks
//   # or directly:
//   compiler/macos_arm64/kcc-arm64 --ir examples/cocoa_hello.ks > /tmp/ch.kir
//   compiler/macos_arm64/macho_host --ir /tmp/ch.kir /tmp/cocoa_hello
//   chmod +x /tmp/cocoa_hello && /tmp/cocoa_hello
//
// State pattern: `stdlib/cocoa.k` is fully stateless, so the caller
// holds every handle (app, win, label, etc.) explicitly. The click
// handler receives `sender` and uses `cocoaSenderTag` to look up its
// own associated state — same approach as Swift's @objc actions, just
// with explicit `funcptr` registration instead of compiler-synthesized
// selectors.
//
// WORKING on macOS arm64 (objk P1-P4 landed): objc_msgSend ABI, NSRect
// struct ABI, and the KrCallbackTarget trampoline are all in the macho
// backend. The window opens and the button click updates the label.
// Non-GUI regression guard for the objc ABI: tests/test_objc_smoke.k.

import "k:cocoa"

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
