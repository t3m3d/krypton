# `stdlib/gui.k` — Krypton GUI library reference

High-level Win32 wrapper. Lets a Krypton program build a native
Windows GUI in 30-50 lines instead of 300+. All strings are UTF-8
end-to-end; the library converts to UTF-16 internally and uses the
W-suffixed Win32 APIs everywhere.

```krypton
import "stdlib/gui.k"
```

Build any program using this library with:

```bat
kcc.exe my_program.k > tmp.c
gcc tmp.c -o my_program.exe -luser32 -lgdi32 -lcomctl32 -lcomdlg32 ^
    -lole32 -lshell32 -ldwmapi -luxtheme -ladvapi32 -lm -w
```

The IDE (`kcode-win`) and `kbackend.exe` already pass these flags.

---

## Lifecycle

| Function | Returns | Purpose |
|---|---|---|
| `guiInit()` | `"1"` | Once at startup. Loads Common Controls v6 manifest, registers the window class, picks Segoe UI 10pt. |
| `guiWindow(title, w, h)` | hwnd | Creates a top-level window centered on the secondary monitor (or primary if only one). Dark titlebar follows OS theme. |
| `guiShow(hwnd)` | `"1"` | Reveals the window after you've placed widgets. |
| `guiRun()` | `"0"` | Blocks running the message loop until the window closes. |
| `guiQuit()` | `"1"` | Posts `WM_QUIT` — exits `guiRun()`. |
| `guiMessageBox(title, msg)` | `"1"` | Modal info popup. |

---

## Basic widgets

All widget creators take a `parent` (the window or container handle)
plus `x, y, w, h` in pixels relative to the parent's client area.

| Function | Returns | Notes |
|---|---|---|
| `guiLabel(parent, text, x, y, w, h)` | hwnd | Static text. |
| `guiButton(parent, label, x, y, w, h)` | id | Wire with `guiOnClick`. |
| `guiTextInput(parent, x, y, w, h)` | hwnd | Single-line edit. |
| `guiTextArea(parent, x, y, w, h)` | hwnd | Multiline edit, vertical scroll. |
| `guiCheckbox(parent, label, x, y, w, h)` | id | `guiIsChecked` / `guiSetChecked`. |
| `guiListbox(parent, x, y, w, h)` | hwnd | `guiListAdd` / `guiListClear` / `guiListSelected`. |
| `guiCombo(parent, x, y, w, h)` | hwnd | Dropdown list. `guiComboAdd` / `guiComboSet` / `guiComboSelected`. |
| `guiProgress(parent, x, y, w, h)` | hwnd | Horizontal progress bar 0-100. `guiProgressSet`. |
| `guiSlider(parent, x, y, w, h)` | id | Trackbar. `guiSliderRange` / `guiSliderSet` / `guiSliderValue`. |
| `guiSpinbox(parent, x, y, w, h)` | hwnd | EDIT + UpDown buddy. Numeric. |
| `guiTreeView(parent, x, y, w, h)` | id | Modern triangle expanders. `guiTreeAdd` / `guiTreeSelected`. |
| `guiTabs(parent, x, y, w, h)` | id | Tab strip. `guiTabAdd` / `guiTabSelected`. |
| `guiDatePicker(parent, x, y, w, h)` | id | Calendar dropdown. `guiDateGet` / `guiDateSet`. |
| `guiScrollbar(parent, x, y, w, h, vertical)` | id | Standalone scrollbar. `guiScrollbarRange` / `guiScrollbarSet` / `guiScrollbarValue`. |
| `guiImage(parent, path, x, y, w, h)` | hwnd | BMP/ICO via Win32, PNG/JPEG/GIF via GDI+. `guiImageSet` to swap. |
| `guiSplitter(parent, x, y, w, h, orient)` | id | Drag-to-resize bar. `guiSplitterPos`. |
| `guiMove(handle, x, y, w, h)` | `"1"` | Reposition any widget. Used by splitter callbacks. |

### Listbox-specific

| Function | What |
|---|---|
| `guiListAdd(listbox, item)` | Append item |
| `guiListClear(listbox)` | Drop all items |
| `guiListSelected(listbox)` | Selected item text, or `""` |

### Combo-specific

| Function | What |
|---|---|
| `guiComboAdd(combo, item)` | Append item |
| `guiComboClear(combo)` | Drop all items |
| `guiComboSelected(combo)` | Selected item text, or `""` |
| `guiComboSet(combo, idx)` | Set selection by index |

### Tree-specific

| Function | What |
|---|---|
| `guiTreeAdd(tree, parent_or_"0", label)` | Returns hex item handle. Pass `"0"` for top-level. |
| `guiTreeClear(tree)` | Drop all items |
| `guiTreeSelected(tree)` | Selected node label, or `""` |

### Tab-specific

| Function | What |
|---|---|
| `guiTabAdd(tabs, label)` | Append tab; returns its index |
| `guiTabSelected(tabs)` | Active tab index, or `"-1"` |

### Date-specific

| Function | What |
|---|---|
| `guiDateGet(picker)` | `"YYYY-MM-DD"` or `""` if invalid |
| `guiDateSet(picker, "YYYY-MM-DD")` | Set the displayed date |

### Slider / Spinbox / Scrollbar-specific

| Function | What |
|---|---|
| `guiSliderRange(slider, lo, hi)` | Set min/max |
| `guiSliderSet(slider, value)` | Set position |
| `guiSliderValue(slider)` | Current position as int string |
| `guiSpinboxRange(spin, lo, hi)` | Set min/max (negatives allowed) |
| `guiSpinboxSet(spin, value)` | Set value |
| `guiSpinboxValue(spin)` | Current value as int string |
| `guiScrollbarRange(sb, lo, hi, page)` | Set range and page size |
| `guiScrollbarSet(sb, value)` | Set position |
| `guiScrollbarValue(sb)` | Current position |

### Progress-specific

| Function | What |
|---|---|
| `guiProgressSet(progress, percent)` | 0-100 |

### Checkbox-specific

| Function | What |
|---|---|
| `guiIsChecked(checkbox)` | `"1"` or `"0"` |
| `guiSetChecked(checkbox, on)` | `1` or `0` |

### Image-specific

| Function | What |
|---|---|
| `guiImageSet(image, path)` | Swap to a different image. Frees the previous bitmap. |

### Splitter-specific

| Function | What |
|---|---|
| `guiSplitterPos(splitter)` | Current x (vertical bar) or y (horizontal) as int string |

Orientation strings: `"vertical"` (thin tall bar, drag left/right) or `"horizontal"` (wide thin bar, drag up/down).

---

## Callbacks

Krypton callback funcs are no-arg — they read state from globals.
Pass them via `funcptr(myFunc)` (bare identifier, NOT a string).

| Function | Use |
|---|---|
| `guiOnClick(handle, funcptr(myFunc))` | Buttons, menu items, checkboxes |
| `guiOnChange(handle, funcptr(myFunc))` | Tree selection, tab change, slider drag, scrollbar drag, splitter drag, combo change, date change |

---

## Setting / reading text

| Function | What |
|---|---|
| `guiSetText(handle, text)` | Update label / input / textarea / etc. |
| `guiGetText(handle)` | Read current text from any control |

---

## Status bar

Persistent bottom strip. **Auto-resizes on window resize** — proportional cells (`*` / `%`) scale automatically.

| Function | What |
|---|---|
| `guiStatusBar(window)` | Create bar, returns handle |
| `guiStatusParts(bar, spec)` | Define cells — see syntax below |
| `guiStatusSet(bar, idx, text)` | Set cell text |
| `guiStatusGet(bar, idx)` | Read cell text |
| `guiStatusIcon(bar, idx, name)` | `"info"` / `"warning"` / `"error"` / `"ok"` / `"question"` / `""` (clear) |
| `guiStatusBgColor(bar, "0xRRGGBB")` | Tint the background. Disables the modern theme on the bar. |

**Parts spec syntax** (comma-separated cells):

| Token | Means |
|---|---|
| `N` | Fixed pixel width |
| `N%` | Percent of bar width |
| `*` | Stretchable; leftover divided equally across `*` cells |
| `-1` | Legacy alias for `*` |

```krypton
guiStatusParts(bar, "*,*,*")          // 3 equal cells
guiStatusParts(bar, "200,*,160")      // fixed, stretch middle, fixed
guiStatusParts(bar, "30%,40%,30%")    // proportional
```

---

## Toolbar

Pinned to top edge, auto-resizes with the window.

| Function | What |
|---|---|
| `guiToolbar(window)` | Create toolbar, returns handle |
| `guiToolButton(tb, label, icon)` | Add button. Returns id (wire with `guiOnClick`). |
| `guiToolSep(tb)` | Vertical divider line |
| `guiToolbarHeight(tb)` | Pixel height (for placing other widgets below it) |

**Built-in icons** (from `IDB_STD_SMALL_COLOR`): `"new"` / `"open"` / `"save"` / `"cut"` / `"copy"` / `"paste"` / `"undo"` / `"redo"` / `"delete"` / `"print"` / `"find"` / `"replace"` / `"help"` / `"props"`. Pass `""` for text-only.

---

## Menu bar

Two flavors:

### Real dropdowns (recommended)

```krypton
let menubar = guiMenuBegin(win)
let m_file  = guiMenu(menubar, "File")        // dropdown column
let mNew    = guiMenuItem(m_file, "New")      // returns id
let mOpen   = guiMenuItem(m_file, "Open")
guiMenuSeparator(m_file)
let mQuit   = guiMenuItem(m_file, "Quit")
guiOnClick(mNew, funcptr(onNew))
```

| Function | What |
|---|---|
| `guiMenuBegin(window)` | Attach a menu bar to the window |
| `guiMenu(menubar, label)` | Add a top-level dropdown column |
| `guiMenuItem(popup, label)` | Add a clickable item to a dropdown |
| `guiMenuSeparator(popup)` | Add a visual divider |

### Flat top-level (legacy)

```krypton
let menu = guiMenuBegin(win)
let m1   = guiMenuAdd(menu, "File: New")        // single click
guiOnClick(m1, funcptr(onNew))
```

---

## Layout stacks

Stop computing y/x manually. A stack pins one axis and lays out widgets along the other. **V-stacks auto-grow their cross axis (width) on window resize.**

```krypton
let lay = guiVStack(parent, x, y, width, gap)
guiVLabel(lay, text, height)
let inp = guiVInput(lay, height)
let btn = guiVButton(lay, label, height)
guiVCheckbox(lay, label, height)
guiVTextArea(lay, height)
guiVProgress(lay, height)
guiVSlider(lay, height)
guiVGap(lay, pixels)                  // empty space
```

Same for horizontal:

```krypton
let row = guiHStack(parent, x, y, height, gap)
guiHLabel(row, text, width)
guiHButton(row, label, width)
guiHInput(row, width)
guiHCheckbox(row, label, width)
guiHGap(row, pixels)
```

Inspect raw stack state if you need to mix in non-stack widgets:

| Function | Returns |
|---|---|
| `guiStackParent(stack)` | Parent hwnd |
| `guiStackX(stack)` | Origin x |
| `guiStackY(stack)` | Origin y |
| `guiStackW(stack)` | Cross size (width for V, height for H) |
| `guiStackH(stack)` | Same as `guiStackW`, alias |
| `guiVNext(stack, h)` / `guiHNext(stack, w)` | Manual cursor advance |

---

## Dock layout

VS-style multi-panel layout. Edges in declaration order, fill takes the leftover. **Auto-relays on window resize.**

```krypton
let dock = guiDock(win)
guiDockTop(dock,    toolbar,    tbHeight)
guiDockBottom(dock, log_panel,  160)
guiDockLeft(dock,   tree,       240)
guiDockRight(dock,  inspector,  220)
guiDockFill(dock,   editor)
guiDockApply(dock)             // initial layout
```

| Function | What |
|---|---|
| `guiDock(window)` | Create dock manager, returns handle |
| `guiDockTop(dock, hwnd, size)` | Pin to top edge with given height |
| `guiDockBottom(dock, hwnd, size)` | Pin to bottom edge with given height |
| `guiDockLeft(dock, hwnd, size)` | Pin to left edge with given width |
| `guiDockRight(dock, hwnd, size)` | Pin to right edge with given width |
| `guiDockFill(dock, hwnd)` | Take whatever's left in the middle |
| `guiDockApply(dock)` | Run initial layout — auto-relays on resize after |

---

## File dialogs

Modal system dialogs. Return path or `""` if cancelled.

| Function | What |
|---|---|
| `guiOpenFile(title, filterCsv)` | "Open" dialog with filter. Returns path. |
| `guiSaveFile(title, filterCsv, defaultName)` | "Save" dialog (with overwrite prompt). Returns path. |
| `guiPickFolder(title)` | Folder browser. Returns folder path. |

**Filter CSV syntax**: `"Label|*.ext1;*.ext2,Other|*.txt"` — pipe between label/pattern, comma between entries. Empty filter defaults to `"All Files|*.*"`.

```krypton
let p = guiOpenFile("Pick image",
                    "Images|*.png;*.jpg;*.gif;*.bmp;*.ico,All|*.*")
```

---

## Color picker

Modal system dialog. Returns `"0xRRGGBB"` or `""`.

```krypton
let c = guiColorPicker("0xFFA657")    // initial color
if len(c) > 0 { guiStatusBgColor(bar, c) }
```

---

## Encoding

Krypton source files are UTF-8. The library converts at every Win32
boundary, so non-ASCII characters work correctly: `"Krypton — 日本語 — café"`
is fine in window titles, labels, list items, status text, etc.

---

## Window placement

`guiWindow` automatically picks the secondary monitor when one
exists, primary otherwise. Helpful when running fullscreen apps on
the primary screen — Krypton GUI windows always land somewhere
visible.

---

## Cross-references

- [Tutorials](../../tutorial/frontend/) — 19 numbered, walkable lessons
- [Examples](../../examples/) — `gui_*.k` files showcasing each widget
- Source: [stdlib/gui.k](../../stdlib/gui.k)
- [Krypton GUI tier roadmap](../krypton_gui_tiers.md) — path from current "Krypton + cfunc" to pure Krypton
