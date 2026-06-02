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

import "k:cocoa"

// Click handler. Receives the sender (the NSButton instance). We use
// envGet on a shared GC env that the main flow attaches to the button
// via cocoaSetAssoc — that's the Cocoa-idiomatic equivalent of a
// closure capture. (envs survive across calls because they're GC heap
// objects, unlike module-level `let` which doesn't init on import.)
func onClick(sender) {
    let env = cocoaGetAssoc(sender)
    let lbl = envGet(env, "label")
    let n   = toInt(envGet(env, "count")) + 1
    envSet(env, "count", "" + n)
    cocoaSetText(lbl, "Clicked " + n + " time(s)")
}

just run {
    let app = cocoaInit()
    let win = cocoaWindow(app, "Hello, KryptScript", 400, 200)

    let lbl = cocoaLabel(win, "Click the button.", 40, 110, 320, 24)
    let btn = cocoaButton(win, "Click me", 150, 50, 100, 32)

    // Stash the click handler's state alongside the button. The
    // trampoline retrieves it via objc_getAssociatedObject when the
    // button fires its action.
    let state = envNew()
    envSet(state, "label", lbl)
    envSet(state, "count", "0")
    cocoaSetAssoc(btn, state)

    cocoaOnClick(btn, funcptr(onClick))
    cocoaShow(win, app)
    cocoaRun(app)
}
