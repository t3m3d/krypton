# objk → Windows: brain_win.ks v0.1

**Agent**: W (Windows)
**Date**: 2026-06-09
**Pairs with**: agent m's `brain.ks` (macOS/Cocoa), agent l's `brain_lin.ks` (Linux/X11 — in flight)

## What landed

`examples/objk/brain_win.ks` — Windows port of `brain.ks`, using the **existing** `stdlib/gui.k` (1689 lines, Win32 bindings, shipped 2026-05-06 per `project_gui_stdlib.md`). No new stdlib needed; `gui.k` already mirrors the cocoa.k API shape:

```krypton
import "k:cocoa"                  // macOS
import "k:gui"                    // Windows  ← brain_win.ks
import "k:x11"                    // Linux  (when l ships)
```

Smoke-tested with `kcc.exe examples/objk/brain_win.ks -o brain_win.exe` → 217 KB native PE, launches, runs the message loop, holds the window open until close.

## API translation table (cocoa → gui)

| cocoa.k                          | gui.k                                  | Notes |
|----------------------------------|----------------------------------------|-------|
| `cocoaInit()`                    | `guiInit()`                            | identical |
| `cocoaWindow(app, t, w, h)`      | `guiWindow(t, w, h)`                   | no app param needed |
| `cocoaShow(win, app)`            | `guiShow(win)`                         | |
| `cocoaRun(app)`                  | `guiRun()`                             | |
| `cocoaTextField(...)`            | `guiTextInput(...)`                    | |
| `cocoaScrollText(...)`           | `guiRichEdit(...)`                     | RichEdit gives same scroll + formatting |
| `cocoaTable(...)` (file list)    | `guiListbox(...)`                      | brain only uses single column |
| `cocoaSegmented(...)`            | `guiTabs(...)`                         | tabs are the closer semantic |
| `cocoaSegLabel`                  | `guiTabAdd`                            | |
| `cocoaSegSelect`                 | `guiTabSelect`                         | |
| `cocoaSegSelected`               | `guiTabSelected`                       | |
| `cocoaSegOnChange`               | `guiOnChange` (on tabs)                | |
| `cocoaOnClick(field, fp)`        | `guiOnClick(field, fp)` (Enter press)  | text-input Enter fires OnClick in gui.k |
| `cocoaMenuBar(app)`              | `guiMenuBegin(win)`                    | |
| `cocoaMenuAdd(bar, label)`       | `guiMenu(bar, label)`                  | |
| `cocoaMenuItem(menu, l, k, fp)`  | `guiMenuAdd(menu, label)`              | no shortcut binding in gui.k yet |
| `cocoaMonoFont(13)` + SetFont    | `guiRichSetMonoFont(rich, "Cascadia Mono", 12)` | |
| `cocoaTVSetString`               | `guiSetText` (on RichEdit)             | |
| `cocoaTVGetString`               | `guiGetText` (on RichEdit)             | |
| `cocoaAlert(t, m)`               | `guiMessageBox(t, m)`                  | |
| `cocoaArray*` / `cocoaNumber*`   | Krypton-native strings/arrays          | no boxing needed |
| `cocoaClass*` + `cocoaSetAssocKey` | module-level `let` variables         | direct fn-ptr callbacks, no class registration |

## What's deferred

- **Live syntax highlighting** — cocoa uses NSTextStorage delegate to recolor on every edit. Windows equivalent is hooking `guiOnChange` to a rescan that calls `guiRichSetFmt` per token range. Doable but ~50 lines and a perf-thoughtful debounce; v0.2.
- **Cmd-O / Cmd-S accelerators on menu items** — `guiMenuAdd(menu, "Open\tCtrl+O")` shows the hint text but doesn't bind the accelerator. Need an accelerator-table wrapper in `gui.k` (`WM_COMMAND` already routes; just no `TranslateAccelerator` setup yet).
- **Tab close button** (Cmd-W in brain.ks). gui.k tabs don't have close glyphs; would need owner-draw or a separate "Close Tab" menu entry.
- **Run output stream** — current `exec()` blocks until done. Brain on mac uses `NSTask` for live streaming. We'd want a Win32 equivalent (`CreateProcess` + named pipe reader thread) for long-running builds.

## Naming + structure

Side-by-side rather than `#ifdef`'d. Same reasoning m wrote in commit `f09e62e2` style — each binding has clean idioms; merging them via macros loses the win.

Three files (when l ships):
- `examples/objk/brain.ks`       — macOS Cocoa
- `examples/objk/brain_win.ks`   — Windows Win32
- `examples/objk/brain_lin.ks`   — Linux X11

A future `brain_main.ks` could platform-dispatch via `arch()` if we ever want a single entry point, but for now the three are independent demos.

## Cross-platform GUI lesson

cocoa.k + gui.k + (forthcoming) x11.k all converged on the **same API shape** independently (Init/Window/Widget/On*/Run). That validates the objk pattern as a real cross-platform UI abstraction. `brain_*.ks` files differ by ~30% (state-storage idiom + a few cocoa-only widgets) — the bulk is shared.

## Next steps

1. Live test brain_win.exe with a real .k project dir, exercise Open/Save/Run.
2. Build accelerator-table wrapper in `gui.k` so menu shortcuts work.
3. Live syntax highlighting on RichEdit via `guiOnChange` + `guiRichSetFmt`.
4. Coordinate naming once stem-rename lands across the site.
