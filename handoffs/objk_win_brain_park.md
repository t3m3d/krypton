# brain (Windows) — parked 2026-06-11

**Status**: working IDE shell, file tree population blocked, parking
to switch to HTML5 ads / VSCode source review.

## What works

- Title bar paints Insiders green via `DwmSetWindowAttribute
  DWMWA_CAPTION_COLOR = 35`.
- Menu strip with all 9 top-level menus (File / Edit / Selection / View
  / Go / Run / Terminal / Window / Help) and full item lists.
- Menu dropdowns open and menu items fire their callbacks. The fix for
  the long-standing "menus do nothing" bug was twofold:
  - `gui.k`'s `_krkWndProc` had `bitAnd(wParam, "65535")` to extract
    `LOWORD(wParam)`; that op-on-string is documented broken
    (`feedback_native_codegen_bugs.md`). Replaced with arithmetic mod
    + stringified id so the `cb.click.<id>` table lookup matches what
    `guiOnClick` writes.
  - `brain_win.ks` now calls `DrawMenuBar(win)` explicitly after every
    `guiMenuItem` has been appended. Without that second call Win11
    refuses to open dropdowns at all (the empty-menu draw at
    `guiMenuBegin` was cached).
- ANSI colour rendering in the bottom console pane.
- `cd` persistence in the integrated terminal.
- File → Open Folder pops the **real modern Win11 Common Item Dialog**
  via IFileOpenDialog COM. Implementation is `_ensurePickerScript()` +
  `_modernPickFolder()` — writes a tiny `.ps1` to `%TEMP%`, then
  `powershell -File <that ps1>`. The `.ps1` `Add-Type`s an inline C#
  defining IFileOpenDialog + IShellItem and calls
  `SetOptions(FOS_PICKFOLDERS = 0x20) + Show + GetResult +
  GetDisplayName(SIGDN_FILESYSPATH)`.
- Syntax highlighting on the editor (purple keywords, peach strings,
  green comments, sage numbers).
- guiStateSet/Get is the global pattern for all widget handles +
  mutable state — module-mutable globals leak via the documented flake.

## What doesn't

- **The picked folder doesn't populate the tree**. The IFileOpenDialog
  returns a clean path, but `Get-ChildItem -LiteralPath '<path>' -Name`
  invoked via `exec()` either returns empty or the result isn't being
  parsed correctly into the TreeView. Diagnostic build is in place
  (the appendConsole "[Get-ChildItem returned N bytes]" + raw output)
  but the next session needs to read the actual diag output to bisect:
  whether `len(listing) == 0` (PS issue) or `len > 0` but `nlines+1`
  loop adds 0 items (parse issue).
- `guiMenuDarken` (added to `stdlib/gui.k`) crashes on launch when
  called. MENUINFO layout is probably wrong (cbSize? hbrBack offset?)
  or `SetMenuInfo` marshalling. Commented out in `brain_win.ks` for
  now.
- Native `guiStatusBar` widget crashes when used in brain's layout.
  Replaced with a `guiLabel` styled as a thin strip.
- Window resize layout: widgets are at fixed pixel coords; enlarging
  the window leaves parent bg visible beyond the last widget. Real fix
  is the `guiDock` helper + a `guiSetTimer(guiDockApply)` poll. Not
  done.
- Most menu items pop "Not implemented yet" (`onTodo`). Wired-for-real
  list: Open File / Open Folder / Save / Save As / Revert / Close
  Editor / Close Folder / Exit; Undo / Redo / Cut / Copy / Paste /
  Select All / Toggle Line Comment; Minimize / Zoom; Brain Help;
  Terminal → New Terminal (= clear console) / Run Active File.

## Files touched

- `stdlib/gui.k` (installed to `C:\krypton\stdlib\`)
- `headers/user32.krh` (installed to `C:\krypton\headers\`)
- `examples/objk/brain_win.ks`
- `examples/objk/_minimal_rich.ks` (kept as the gui.k smoke test)

## How to resume

1. `cd c:\Users\brian\Documents\GitHub\krypton`
2. `kcc examples/objk/brain_win.ks -o c:\tmp\brain_win.exe`
3. Patch PE subsystem CUI→GUI: see `stem/build_windows.sh` for the
   Python one-liner.
4. Launch. Diag output in the console will show what
   `Get-ChildItem -Name` returned for the picked folder; from there
   either fix the PS quoting or fix the parsing loop.
