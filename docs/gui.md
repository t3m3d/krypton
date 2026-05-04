# Krypton GUI Programs (Windows, C path)

**Available as of 1.5.1.** Krypton can build Windows GUI programs that
ship as a single standalone `.exe` — no Python, no separate frontend
process, no .NET, no Qt. The current path goes through the C emitter
(`kcc → C → gcc`) and links against the same Win32 DLLs every C/C++
GUI program uses (`user32.dll`, `gdi32.dll`).

The pure-native pipeline (no gcc) doesn't yet support GUI work — Tier 3
on the 1.6 roadmap covers callbacks, which is the missing piece. Until
then, GUI programs build the same way kmon does: `.k` source files
that mix Krypton with `cfunc { }` blocks for the parts the language
can't yet express directly.

## Anatomy of a GUI program

Every Win32 GUI program has the same five-part skeleton:

1. **WindowProc** — a callback the OS calls with messages (`WM_PAINT`,
   `WM_COMMAND`, `WM_DESTROY`, etc.). Lives in a `cfunc { }` block
   today because Krypton can't yet emit the C calling-convention
   entry stub the OS expects.
2. **Window class registration** — `RegisterClassExA(&wc)` with a
   `WNDCLASSEXA` struct that holds the WindowProc pointer. Lives in
   the same `cfunc` block as WindowProc, since wiring the function
   pointer into the struct is easier in C than crossing the Krypton
   boundary.
3. **Window creation** — `CreateWindowExA(...)`. Can be done from
   either Krypton or `cfunc`; in the examples below we keep it in the
   `cfunc` block for symmetry.
4. **Message pump** — `GetMessageA` / `TranslateMessage` /
   `DispatchMessageA`. *This part is pure Krypton.* Uses the bindings
   from `headers/user32.krh`.
5. **Exit** — when the user closes the window, `WM_DESTROY` calls
   `PostQuitMessage(0)`, which causes `GetMessageA` to return 0. The
   Krypton `while` loop exits and `just run` returns.

## Headers you'll import

| Header | DLL | Use |
|--------|-----|-----|
| `headers/windows.krh` | kernel32 + others | GUI structs (`POINT`, `RECT`, `MSG`, `WNDCLASSEXA`, `PAINTSTRUCT`, `CREATESTRUCTA`) |
| `headers/user32.krh` | user32.dll | Window classes, message pump, paint, dialogs, input, timers |
| `headers/gdi32.krh` | gdi32.dll | Text drawing, pens / brushes / fonts, shapes, bitmaps |
| `headers/comdlg32.krh` | comdlg32.dll | File open / save, colour picker, font picker, print, find / replace |
| `headers/comctl32.krh` | comctl32.dll | Common controls — list view, tree view, tab control, status bar, toolbar, progress bar, slider, spin |

Link line:

```
gcc tmp.c -o myapp.exe \
  -luser32 -lgdi32 \
  -lpsapi -lpdh -lshell32 -ladvapi32 \
  -lm -w
```

The `psapi`/`pdh`/`shell32`/`advapi32` flags are pulled in transitively
by `windows.krh` declaring functions from those DLLs — they need
link-time resolution even if your program doesn't call them. (The
Tier 1.6 work on splitting `windows.krh` will reduce this surface.)

## Three example programs

All in `examples/`:

### `win_messagebox.k` — smallest possible GUI

Six lines of Krypton, single `MessageBoxA` call. Builds to 421 KB.

```krypton
import "user32.krh"

just run {
    MessageBoxA("0", "Hello from Krypton!", "Krypton GUI", "64")
    kp("dialog dismissed")
}
```

No window class, no message pump, no `cfunc` — `MessageBoxA` is a
self-contained modal dialog that blocks until the user clicks OK.

### `win_hello.k` — first real-window program

Opens a normal resizable window, paints "Hello from Krypton!" via
`TextOutA`, runs a Krypton-side message pump, exits cleanly when the
user closes the window. 449 KB.

WindowProc + class registration + window creation: `cfunc` block
(~30 lines of C). Message pump: 7 lines of Krypton.

### `win_counter.k` — child controls + click handlers

Adds buttons. A `STATIC` label shows the current count, a `−` button
decrements it, a `+` button increments it. Demonstrates:

- Creating child windows with the built-in `STATIC` and `BUTTON`
  classes (no extra registration — those classes ship with user32)
- Dispatching `WM_COMMAND` by control ID (`LOWORD(wParam)`)
- Live-updating UI with `SetWindowTextA`

Same Krypton-side message pump as `win_hello`. 448 KB.

### `win_textinput.k` — text entry

`EDIT` control + three transform buttons (Reverse / Upper / Clear).
Shows how to read text from an input field with `GetWindowTextA`
and write a result back to a label. 449 KB.

### `win_paint.k` — mouse-driven canvas

Drag-to-draw paint program. Captures `WM_LBUTTONDOWN` /
`WM_MOUSEMOVE` / `WM_LBUTTONUP`, uses `SetCapture` / `ReleaseCapture`
for off-window dragging, persists strokes to an off-screen
`CreateCompatibleBitmap` so window resizes preserve the drawing.
Toolbar of colour-switching buttons; right-click clears the canvas.
455 KB.

### `win_filedialog.k` — standard Windows file picker

`GetOpenFileNameA` from `comdlg32.krh` opens the system file
dialog. The selected path appears in a read-only `EDIT` field; the
first 512 bytes of the file load into a multi-line preview pane.
The full `OPENFILENAMEA` struct stays in `cfunc` (24 fields are
easier to fill in C); Krypton just calls a tiny helper that returns
the chosen path as a string. 452 KB.

### `win_listview.k` — data grid + status bar

`SysListView32` in report mode with three columns, full-row select,
click-to-sort column headers, grid lines, two-pane
`msctls_statusbar32` at the bottom. Demonstrates `InitCommonControlsEx`,
`LVM_*` / `SB_*` messages via `SendMessageA`, and `WM_NOTIFY`
dispatch for `LVN_ITEMCHANGED` / `LVN_COLUMNCLICK`. 457 KB.

### `win_notepad.k` — menu bar + multi-line editor

Real menu bar (File / Edit / Help) with the standard items every
Windows app ships. File>Open and File>Save As go through
`comdlg32`'s `GetOpenFileNameA` / `GetSaveFileNameA`. Edit-menu
items route to `WM_CUT` / `WM_COPY` / `WM_PASTE` / `EM_SETSEL` via
`SendMessageA`. Fixed-width Consolas font via `CreateFontA`. 462 KB.

## Idioms

### Typed structs vs. env structs

The new GUI structs are **typed structs** declared via
`jxt struct { ... }` in `windows.krh`. Use the typed accessors with
an explicit type-name argument — *not* the env-style `setField`/
`getField`:

```krypton
let r = structNew("RECT")
structSet(r, "RECT", "left", "10")
let l = structGet(r, "RECT", "left")    // returns "10"
```

Mixing the two APIs silently corrupts data. The env API
(`envNew` / `setField` / `getField`) is for ad-hoc string-keyed
dictionaries and should not be used on `jxt struct` instances.

### Where to put callbacks

Anything Windows calls back into (WindowProc, dialog procs, hook
procs, timer callbacks via `SetTimer`) needs a C function with the
right calling convention. Today that means `cfunc { }`. Once Tier 3
lands, `callback func` (already a Krypton keyword) will emit
WindowProc-shaped stubs the native pipeline can use, and you'll be
able to write the WindowProc in Krypton directly.

### Strings and integer-flag arguments

Krypton strings round-trip through the C-path wrappers as `char*`.
The Win32 functions that take integer flags get the string parsed
back via `atoi` in the wrapper, so a Krypton call like:

```krypton
MessageBoxA("0", "msg", "title", "64")    // 64 = MB_ICONINFORMATION
```

works the same as the C equivalent `MessageBoxA(NULL, "msg",
"title", MB_ICONINFORMATION)`. Pass numeric flags as decimal strings.

For pointer-typed arguments (HWND, HINSTANCE, etc.), pass `"0"` for
NULL. Pointers returned from Win32 functions come back as
Krypton-side `char*` strings whose value *is* the pointer — pass
them directly to other Win32 calls without any conversion.

## What's coming

| Capability | Status |
|------------|--------|
| Open a window | ✓ shipped 1.5.1 |
| Buttons, text labels, single-line text input | ✓ shipped 1.5.1 (use built-in classes) |
| Modal dialogs (`MessageBoxA`) | ✓ shipped 1.5.1 |
| Mouse capture + custom drawing | ✓ shipped 1.5.1 (see `win_paint.k`) |
| Common dialogs (file open/save, color, font) | ✓ shipped 1.5.1 via `comdlg32.krh` |
| Multi-line text view | ✓ shipped 1.5.1 (use `EDIT` with `ES_MULTILINE`) |
| Common controls (list view, status bar, toolbar) | ✓ shipped 1.5.1 via `comctl32.krh` |
| Tree view, tab control, progress bar, slider | ✓ binding shipped — patterns documented but no example yet |
| Menu bars + popup menus | ✓ shipped 1.5.1 (see `win_notepad.k`) |
| Native pipeline (gcc-free) GUI | not yet — Tier 1 + Tier 3 + native typed-struct expansion |
| WindowProc in pure Krypton | not yet — Tier 3 native callbacks |
| Higher-level wrappers (`stdlib/ui/`) | future, after Tier 3 |
