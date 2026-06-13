# w → m : Objective-K is `.ks` + `import "k:cocoa"`, not a new dialect

**From:** agent w (Windows)
**To:** agent m (macOS)
**Date:** 2026-06-13
**Re:** convention lock-in before parallel work forks.

## Decision

`.objk` as a separate file extension / dialect is **not happening**.
Objective-K is just **KryptScript (`.ks`) with the Cocoa surface
imported**. One file extension, one runtime, platform behavior via
`import`.

```krypton
#!/usr/bin/env kr

import "k:cocoa"

just run {
    let win = NSWindow.new(800, 600, "Hello")
    win.show()
    krApp.run()
}
```

On macOS that pulls in real Cocoa bindings; on Windows / Linux the
import resolves to either compile-time errors with a clear "Cocoa
unavailable on this platform" message or to no-op stubs depending on
what your `cocoa.k` module decides.

## Why

- One extension to teach. `.ks` = "ergonomic Krypton."
- objk gets every KryptScript win for free — shebang, `kr file.ks`,
  `kcc -r`, REPL.
- Cocoa is a library, not a language. Baking it into a file extension
  is a category mistake.
- Cross-platform `.ks` programs can target whatever surface they
  `import`; the user doesn't change extensions when switching backends.

Matches the headline framing in `handoff_w2all_overall.md`:
**Python-style FE + C++-grade capability**. KryptScript = the
Python-style FE; Cocoa / Win32 / GTK = the C++-grade capability
layers — all behind `import`.

## What this means for the work you've already done

Nothing gets thrown away. Your `headers/objc.krh` + any
`stdlib/cocoa.k` you ship are exactly the surface that an
`import "k:cocoa"` line resolves to. Same call sites, same patterns.
The only thing that changes is what we *call* it — Objective-K is the
**library surface**, not the file dialect.

If you've been calling files `*.objk` locally, please rename to
`*.ks` before pushing so the tree stays consistent.

## Heads-up: agent l is implementing some Objective-K shapes in `.ks`

Per Brian, l is going to ship some Cocoa-style surface as `.ks`
programs. That's the convention from this point forward. Coordinate
with l if your `stdlib/cocoa.k` surface overlaps anything they're
landing — better to agree on names once than rename later.

## Parallel rewrite-Cocoa discussion (FYI, not action item yet)

There's a longer-term conversation about whether macOS Krypton GUI
should be **a Cocoa bridge** (your current work) or **a Krypton-native
widget toolkit** that talks to Quartz / CoreGraphics directly without
linking AppKit. The latter would unify `stdlib/gui.k` across all three
OSes — Win32 backend (shipped), Quartz backend (would be new), GTK / X11
backend (would be new on l's side).

Not deciding that today. Just flagging that if it goes that way, your
Cocoa bridge becomes `k:cocoa` — the "I want real NSWindow chrome
specifically" escape hatch — and a separate `k:gui` becomes the
default cross-platform surface. Both ship.

— w

[[handoff_w2all_overall]] [[w2l_memory]]
