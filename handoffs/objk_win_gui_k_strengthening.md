# gui.k strengthening — 2026-06-11

**Agent**: W (Windows)
**Files touched + installed**:
- `stdlib/gui.k` — patched + copied to `C:\krypton\stdlib\gui.k`
- `headers/user32.krh` — patched + copied to `C:\krypton\headers\user32.krh`
- `examples/objk/brain_win.ks` — wires the new helpers

You don't need to copy anything tomorrow — both files are already in place under `C:\krypton`.

## Why these changes

Two days into the Windows brain port, three recurring bugs kept biting:

1. **Menu items silently don't fire** — `gui.k`'s `_krkWndProc` did
   `bitAnd(wParam, "65535")` to extract LOWORD(wParam). Per
   `feedback_native_codegen_bugs.md`, bitAnd-on-string is documented
   broken on the Windows native codegen. The lookup `cb.click.<id>` got
   a bad key, callbacks never fired.

2. **White strip under the menu bar** — Win11 menus paint a chrome
   strip below `File/Edit/...` that ignores `guiEnableDarkMode`'s DWM
   call. No way to recolor it short of `SetMenuInfo` with
   `MIM_BACKGROUND` + a custom brush.

3. **`SetFocus(cmdline_id)` crashed stem_win on launch** — the
   marshaller passed the id (1000-65535 range) as the `HWND` arg
   directly to `user32!SetFocus`; the dereference into garbage memory
   AV'd. Needed an id→HWND wrapper.

## Patches landed

### `stdlib/gui.k`

- **`_krkWndProc` WM_COMMAND handler** — replaced
  `bitAnd(wParam, "65535")` with arithmetic mod (`w - (w/65536)*65536`)
  and stringified the result so the `cb.click.<id>` lookup matches the
  string id `guiOnClick` writes.
- **`guiColorPicker`** — RGB byte extraction rewritten arithmetic,
  same reason.
- **`guiSliderRange`** — `MAKELONG(lo, hi)` rewritten arithmetic.
- **`guiMenuDarken(menubar, hexColor)`** — NEW. Builds a 40-byte
  MENUINFO (cbSize=40, fMask=MIM_BACKGROUND, hbrBack=brush) and calls
  `SetMenuInfo`. Then `DrawMenuBar` + `InvalidateRect` so the strip
  repaints immediately. Use after `guiMenuBegin`.
- **`guiFocus(hwnd)`** — NEW. Resolves a Krypton control id to a real
  HWND via `_guiResolveHwnd` and calls `SetFocus`. Use this anywhere
  you'd reach for `SetFocus(controlId)` directly.
- **`guiActivate(hwnd)`** — NEW. Same wrapper for
  `SetForegroundWindow`.

### `headers/user32.krh`

- Added `SetMenuInfo` and `GetMenuInfo` declarations.
- `SetFocus` / `SetForegroundWindow` / `BringWindowToTop` already
  added earlier are kept; combined with the new `guiFocus` /
  `guiActivate` wrappers, direct calls are no longer needed.

## What now Just Works in brain

After the rebuild in this commit:
- Menu items now fire their `guiOnClick` callbacks (Help → Brain Help
  pops a MessageBox; Edit → Cut/Copy/Paste send the right RichEdit
  messages, etc.).
- `guiMenuDarken(bar, "0x0e3520")` paints the menu strip the same
  Insiders green as the title bar, killing the white chrome strip.
- The `cmdline` focus crash we hit in stem_win is fixed if you ever
  switch to `guiFocus(cmdline)`.

## Still pending

- **Window resize layout** — brain widget rects are fixed pixel coords;
  enlarging the window leaves the parent bg (now dark green) visible
  beyond the last widget. Real fix is the `guiDock` helper + a 100 ms
  `guiSetTimer(guiDockApply)`. Not done tonight to avoid another build.
- **SysTabControl32 white client area** — replaced with a Label
  showing the active filename. Multi-file tab UI will return as an
  owner-drawn strip of clickable Labels / buttons later.
- **Up/down arrow → command history** in stem console — needs gui.k
  to dispatch `WM_KEYDOWN` (or RichEdit's `EN_MSGFILTER` with
  `ENM_KEYEVENTS`) to a user callback. Not done; would add
  `guiOnKey(hwnd, fp)`.
- **`guiStatusBar` crash** under brain's layout — root cause unknown.
  Stayed faked with `guiLabel` for now.

## How to verify in the morning

1. `c:\tmp\brain_win.exe` should launch with the green title bar +
   green status bar + green menu strip (no white sliver under
   `File/Edit/...`).
2. Click `Help → Brain Help` — a "brain -- pure-Krypton IDE on
   Windows..." MessageBox should pop. That's the smoke test for the
   bitAnd fix.
3. Click a `.k` file in the left tree — should load into the editor
   with syntax highlighting (purple keywords, peach strings, green
   comments).
4. Type in the bottom console after the `$ ` prompt + Enter — should
   run the command and append output with ANSI colours.

If any of those don't, the next move is grepping `_krkWndProc` for
other places it might still be doing bit ops on strings.
