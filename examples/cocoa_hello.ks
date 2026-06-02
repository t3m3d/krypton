#!/usr/bin/env kr
// examples/cocoa_hello.ks — Minimal Cocoa app written in pure Krypton.
//
// Native macOS arm64 window with a label and a button. Click the button,
// the label updates. Nothing else. Conceptually identical to the
// 30-line Swift / Objective-C "hello AppKit" tutorials, but written
// against stdlib/cocoa.k — every line is just Krypton.
//
// Build + run (macOS arm64):
//   kr cocoa_hello.ks                  # or: kcc -r cocoa_hello.ks
//
// SCAFFOLD — runs on macOS arm64 once agent m lands the macho codegen
// for objc_msgSend + NSRect ABI + the callback bridge for cocoaOnClick.
// On Windows / Linux today this is just paper: it parses, but the
// Cocoa symbols won't resolve at link time.

import "k:cocoa"

let label = ""
let clicks = 0

func onClick() {
    clicks = clicks + 1
    msg_1(label, sel_setStringValue, nsString("Clicked " + clicks + " times"))
}

just run {
    cocoaInit()

    let win = cocoaWindow("Hello, KryptScript", 400, 200)

    label = cocoaLabel(win, "Click the button.", 40, 110, 320, 24)

    let btn = cocoaButton(win, "Click me", 150, 50, 100, 32)
    cocoaOnClick(btn, funcptr(onClick))

    cocoaShow(win)
    cocoaRun()
}
