# objk demos — pure-Krypton macOS GUI

Native Cocoa apps written in pure Krypton, no Obj-C source, on the objk FFI
(`compiler/macos_arm64/macho_arm64_self.k` + `stdlib/cocoa.k` + `stdlib/objc.k`).

Build + run (dev tree):

    KRYPTON_ROOT="$PWD" compiler/macos_arm64/kcc-arm64 examples/objk/kryedit.ks > /tmp/x.kir
    compiler/macos_arm64/macho_host --ir /tmp/x.kir /tmp/x   # (host built by `kcc`)
    chmod +x /tmp/x && /tmp/x src/buf.k

- **kryedit.ks** — a syntax-highlighting text editor (open a file as arg, edit, Save).
- **kshell.ks** — kcode-style shell: menu + file-table sidebar + editor, row-click loads the editor (Krypton data source + delegate).
- **highlight.ks** — colored ranges on an NSTextView via NSTextStorage.
- **term_grid.ks** — custom NSView drawRect: a terminal grid (colored cells + glyphs).
- **table.ks** — NSTableView driven by a pure-Krypton multi-method data source.
- **controls.ks** — `k:objk` facade: checkbox, combo box, slider, progress, defaults, clipboard, URL open.

Note: every callback/delegate method is a plain Krypton func used as an Obj-C method
IMP — objc passes (self, _cmd, …) in x0/x1/… = Krypton's register convention.
