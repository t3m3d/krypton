# stem_win.ks → v0.1.3 — two bugs found, both root-cause of "blank window"

**Agent**: W (Windows)
**Date**: 2026-06-10 (late night)
**Commit**: `f0b01f6`

## TL;DR

The Windows brain/stem ports built fine but rendered a black-on-black void.
Two compounding bugs:

1. **Hex color literals need `0x` prefix**. `gui.k`'s `_guiHexToInt` only
   recognises `"0xRRGGBB"`; `"RRGGBB"` falls through to `toInt(...)` →
   returns 0 → COLORREF 0 = pure black → invisible on the dark theme bg.
2. **Module-level mutable globals read garbage across functions**. The
   `feedback_module_mutable_globals.md` flake. `appendOutput()` reading
   `g_output` got 0 even though `just run` had just assigned it the
   RichEdit hwnd. `guiRichAppend(0, ...)` is a silent no-op.

After fixing both, `stem_win.exe` renders the boot banner, dark theme
applies, title bar tracks cwd. Captured screenshots prove it.

## Smoke A vs B (the diagnostic)

```krypton
just run {
    ...
    g_output = guiRichEdit(...)
    guiRichAppend(g_output, "A inline\n", "0xffffff", "0")  // SHOWS
    appendOutput("B via wrapper\n")                          // INVISIBLE
}
```

Inline `g_output` read inside `just run`'s own scope works. The same
identifier read from inside `appendOutput()` returns 0. That's the
mutable-global bug. Workaround: `guiStateSet/Get`.

## Fix pattern (stem_win.ks v0.1.3)

```krypton
// Accessor helpers — each is a one-liner reading guiStateGet.
func _o()       { emit guiStateGet("stem.output") }
func _ci()      { emit guiStateGet("stem.cmdline") }
func _wh()      { emit guiStateGet("stem.win") }
func _cwdG()    { emit guiStateGet("stem.cwd") }
func _cwdS(v)   { guiStateSet("stem.cwd", v)  emit "1" }
func _fgG()     { emit guiStateGet("stem.curFg") }
func _fgS(v)    { guiStateSet("stem.curFg", v)  emit "1" }
...

// in just run after creating widgets:
guiStateSet("stem.win", win + "")
guiStateSet("stem.output",  output + "")
guiStateSet("stem.cmdline", cmdline + "")

// in functions: never reference g_xxx, always _o(), _ci(), etc.
func appendOutput(s) {
    ...
    guiRichAppend(_o(), buf, _fgOrDefault(), _boldGet())
    ...
}
```

Performance cost: one guiStateGet per access (hash lookup). For terminal
output streams, negligible.

## What still needs the same treatment

- `examples/objk/brain_win.ks` — 69 module-global references; same
  bugs, never visually validated. Needs the same `guiStateSet/Get`
  rewrite. (The 0x color prefix has already been applied via the
  selective-regex script.)
- `examples/objk/stem_win_pty.ks` — same widget globals, but the
  current blocker there is ConPTY init crash, not rendering.

## Other gotchas hit (worth saving as feedback memos)

- **Em-dash mojibake**: `—` in Krypton source → UTF-8 bytes in RichEdit
  → renders as `â€"` because RichEdit is in the ANSI code page by
  default. Fix tonight: use `--`. Real fix would mirror terk's UTF-8
  manifest (`project_terk_utf8_manifest.md`).
- **gui_hello.k uses Label/Button/TextInput only** — `guiRichEdit`
  was never visually validated before; hence both bugs above sat
  unnoticed in `gui.k`. The minimal-test pattern
  (`examples/objk/_minimal_rich.ks`, 17 lines) is the way to validate
  future widget additions.
- **PE subsystem stays CUI by default** — `kcc -o` doesn't expose a
  `--subsystem windows` flag, so GUI apps spawn a console window on
  launch. One-byte patch at `e_lfanew + 24 + 0x44` flips CUI(3) → GUI(2).
  Would be nice as a kcc flag.

## Known limitations of v0.1.3

- **No input focus on launch** — GUI-subsystem `stem.exe` doesn't get
  foreground focus when launched from Explorer / Start-Process. User
  has to click the window before typing. `SetForegroundWindow` /
  `SetFocus` aren't in `head:windows.krh` yet.
- **Per-command exec()** — still the v0.1 command-runner model. ConPTY
  interactive is in `stem_win_pty.ks` (parked on a Win32 segfault).
- **Sendkeys-driven smoke test couldn't confirm Enter→onCmd** because
  of the focus issue. Visual confirmation pending user-driven test.

## What landed

- `examples/objk/stem_win.ks` rewritten to v0.1.3 (guiState pattern,
  0x colors, ASCII boot text).
- `examples/objk/_minimal_rich.ks` — 17-line validation test for
  RichEdit + colors. Keep for future widget validations.
- 0x color prefix applied to `brain_win.ks` + `stem_win_pty.ks`
  (selective regex, only literals with a-f chars; pure-digit constants
  preserved).

## Next steps

1. Apply guiStateSet/Get pattern to `brain_win.ks` (69 refs).
2. Test input flow in stem (user-driven, click window first).
3. Bind `SetForegroundWindow`/`SetFocus` in `head:windows.krh`; add
   one-liner to `guiShow` to grab focus.
4. Add `--subsystem windows` flag to kcc instead of the PE patch
   trick.
5. Resume ConPTY bisection in stem_win_pty (parked).
