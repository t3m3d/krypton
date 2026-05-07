# Krypton Frontend Tutorial

Hands-on guide to writing GUI programs with `stdlib/gui.k`. Each numbered
file builds on the previous; copy and run them in order.

```
01_hello_window.k     A blank window — guiWindow / guiShow / guiRun
02_button.k           Click handler — guiButton + guiOnClick + guiMessageBox
03_input.k            Read user text — guiTextInput + guiGetText
04_layout.k           Multi-widget layout with labels + spacing
05_listbox.k          Dynamic list — guiListbox / guiListAdd / guiListSelected
06_checkbox.k         Toggle state — guiCheckbox / guiIsChecked / guiSetChecked
07_progress.k         Progress bar — guiProgress / guiProgressSet
08_treeview.k         Hierarchy with triangles — guiTreeView + guiTreeAdd
09_tabs.k             Multi-page UI — guiTabs / guiTabAdd / guiOnChange
10_menu.k             Top menu bar — guiMenuBegin / guiMenuAdd
11_status_bar.k       Bottom strip — guiStatusBar with parts/icons/tints
12_putting_together.k Full tiny app combining everything above
```

---

## Build & run

Every `.k` file in this folder builds the same way:

```bat
:: From the krypton repo root
kcc.exe tutorial\frontend\01_hello_window.k > tmp.c
gcc tmp.c -o hello.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi -luxtheme -ladvapi32 -lm -w
hello.exe
```

The kcode-win IDE's F5 already passes the right link flags so you can just
hit F5 on any of these files.

---

## API cheat sheet

### Lifecycle

| Call | Returns | Purpose |
|---|---|---|
| `guiInit()` | "1" | Once at startup. Loads modern theme, registers window class, picks Segoe UI. |
| `guiWindow(title, w, h)` | hwnd | Creates a top-level window centered on the monitor *opposite* the cursor. |
| `guiShow(hwnd)` | "1" | Reveals the window after you've placed widgets. |
| `guiRun()` | "0" | Blocks running the message loop until the window closes. |
| `guiQuit()` | "1" | Posts WM_QUIT — exits `guiRun`. |
| `guiMessageBox(title, msg)` | "1" | Modal info popup. |

### Widgets

All widget creators take `parent` (the window or a container) plus
`x, y, w, h` in pixels relative to the parent's client area.

| Function | Returns | Notes |
|---|---|---|
| `guiLabel(parent, text, x, y, w, h)` | "1" | Static text. |
| `guiButton(parent, label, x, y, w, h)` | id | Wire with `guiOnClick`. |
| `guiTextInput(parent, x, y, w, h)` | hwnd | Single-line edit. |
| `guiTextArea(parent, x, y, w, h)` | hwnd | Multiline edit, vertical scroll. |
| `guiCheckbox(parent, label, x, y, w, h)` | id | `guiIsChecked` returns `"1"` / `"0"`. |
| `guiListbox(parent, x, y, w, h)` | hwnd | `guiListAdd` / `guiListClear` / `guiListSelected`. |
| `guiProgress(parent, x, y, w, h)` | hwnd | `guiProgressSet(hwnd, percent)` 0–100. |
| `guiTreeView(parent, x, y, w, h)` | id | `guiTreeAdd(tree, parent_or_"0", label)`. Modern triangles. |
| `guiTabs(parent, x, y, w, h)` | id | `guiTabAdd(tabs, label)` per page. |

### Callbacks

| Function | Use |
|---|---|
| `guiOnClick(handle, funcptr(myFunc))` | Buttons, menu items, checkboxes. |
| `guiOnChange(handle, funcptr(myFunc))` | Tree selection, tab change. |

`myFunc` is a no-arg Krypton func — read state from globals or via
`guiGetText` / `guiTreeSelected` / `guiTabSelected`.

### Status bar

Persistent, very flexible bottom strip with multiple cells, icons, and
tints. **Re-applies on window resize** — proportional cells (`*` / `%`)
scale automatically.

| Function | Notes |
|---|---|
| `guiStatusBar(window)` | Creates the bar, returns handle. |
| `guiStatusParts(bar, spec)` | Define cells — see Spec syntax below. |
| `guiStatusSet(bar, idx, text)` | Set cell text. |
| `guiStatusGet(bar, idx)` | Read cell text back. |
| `guiStatusIcon(bar, idx, name)` | `"info"` / `"warning"` / `"error"` / `"ok"` / `"question"` / `""`. |
| `guiStatusBgColor(bar, "0xRRGGBB")` | Tint background. Disables theme on the bar. |

**Status bar parts spec syntax** (comma-separated cells):

```
N        fixed pixel width      e.g.  200
N%       percent of bar width   e.g.  25%
*        stretchable            leftover divided equally
-1       legacy alias for *
```

Examples:

```krypton
guiStatusParts(bar, "*,*,*")          // 3 equal cells, scale on resize
guiStatusParts(bar, "200,*,160")      // fixed, stretch middle, fixed
guiStatusParts(bar, "30%,40%,30%")    // proportional
guiStatusParts(bar, "180,*")          // 2 cells, label + main
```

---

## Patterns to remember

1. **Module-level globals for state shared across callbacks.**
   `let g_input = ""` at the top of the file, callbacks reference it.
2. **`funcptr(myCallback)`** — bare identifier, NOT a string. The callback
   must be a `func` defined at module level.
3. **Always `guiInit()` first**, then create your window, then call
   `guiShow()` AFTER placing all widgets, then `guiRun()` to enter the
   event loop.
4. **Status bar parts spec is sticky** — set once with `guiStatusParts`
   and the bar will re-flow on every resize automatically.
5. **Keep strings ASCII** for now — Win32 ANSI APIs render bytes as
   windows-1252, so non-ASCII characters become mojibake. A future
   tier of `gui.k` will switch to wide-string APIs.

---

## Where each tutorial lives

These files are walkable in numeric order — each adds one concept.
See [01_hello_window.k](01_hello_window.k) to start.
