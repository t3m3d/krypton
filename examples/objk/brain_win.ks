// brain_win.ks — Windows port of brain.ks (the pure-Krypton IDE).
//
// Mirrors brain.ks (macOS, k:cocoa) using the existing k:gui stdlib
// (Win32, stdlib/gui.k). Single source file pattern stays: same layout
// (tree + tabs + editor + console + cmdline), same Open/Save/Run flow.
//
// Build:
//   kcc.exe examples/objk/brain_win.ks -o brain.exe
//   .\brain.exe <project-dir>
//
// Cross-platform pairing:
//   examples/objk/brain.ks      — macOS / Cocoa  (k:cocoa)
//   examples/objk/brain_win.ks  — Windows / Win32 (k:gui)
//   examples/objk/brain_lin.ks  — Linux / X11    (k:x11) — agent L, in flight
//
// The three are intentionally side-by-side rather than a single
// platform-switching file: each binding has slightly different idioms
// (Cocoa's NSTextStorage delegate vs Win32 RichEdit WM_CHANGE) and
// hiding the difference behind a #ifdef-style wrapper would obscure
// what's actually a clean platform-native expression in each case.

import "k:gui"

// ── module-level state ────────────────────────────────────────────────
// Replaces brain.ks's cocoaSetAssocKey(app, "brain.x", ...) pattern.
// Win32 has SetWindowLongPtr(GWLP_USERDATA) for per-HWND state, but
// brain's state is application-global, so plain module-let is cleanest.

let g_dir       = ""    // project directory (argv[0])
let g_win       = 0     // main window HWND
let g_tree      = 0     // file listbox (left column)
let g_tabs      = 0     // tab control (top of editor area)
let g_editor    = 0     // RichEdit — main editor
let g_console   = 0     // RichEdit — read-only output pane
let g_cmdline   = 0     // text input — command runner

let g_files     = ""    // \n-separated list of filenames in g_dir
let g_tabpaths  = ""    // \n-separated list of open tab full paths
let g_tabtexts  = ""    // \x1F-separated tab buffer contents (\x1F = unit separator, safe vs newlines in code)
let g_curtab    = 0 - 1 // active tab index, -1 == none

// ── helpers ───────────────────────────────────────────────────────────

func baseName(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        if p[i] == "/" { emit substring(p, i + 1, n) }
        if p[i] == "\\" { emit substring(p, i + 1, n) }
        i = i - 1
    }
    emit p
}

func splitLines(s) { emit s }   // we keep \n-strings; iterate via lineCount + nthline (utils.k pattern)
func nlines(s) {
    let n = len(s)  let c = 0  let i = 0
    while i < n { if s[i] == "\n" { c = c + 1 }  i = i + 1 }
    emit c
}
func lineAt(s, idx) {
    let n = len(s)  let cur = 0  let start = 0  let i = 0
    while i < n {
        if s[i] == "\n" {
            if cur == idx { emit substring(s, start, i) }
            cur = cur + 1  start = i + 1
        }
        i = i + 1
    }
    if cur == idx { emit substring(s, start, n) }
    emit ""
}

// Splits g_tabtexts on \x1F. Returns the idx'th chunk or "".
func tabTextAt(idx) {
    let SEP = fromCharCode(31)
    let n = len(g_tabtexts)  let cur = 0  let start = 0  let i = 0
    while i < n {
        if g_tabtexts[i] == SEP {
            if cur == idx { emit substring(g_tabtexts, start, i) }
            cur = cur + 1  start = i + 1
        }
        i = i + 1
    }
    if cur == idx { emit substring(g_tabtexts, start, n) }
    emit ""
}
func tabTextSet(idx, text) {
    let SEP = fromCharCode(31)
    let n = len(g_tabtexts)  let cur = 0  let start = 0  let i = 0
    let out = ""
    while i <= n {
        let atSep = 0
        if i == n { atSep = 1 }
        if i < n  { if g_tabtexts[i] == SEP { atSep = 1 } }
        if atSep == 1 {
            if cur == idx { out = out + text }
            if cur != idx { out = out + substring(g_tabtexts, start, i) }
            if i < n     { out = out + SEP }
            cur = cur + 1  start = i + 1
        }
        i = i + 1
    }
    g_tabtexts = out
    emit "1"
}
func tabTextAdd(text) {
    let SEP = fromCharCode(31)
    if len(g_tabtexts) > 0 { g_tabtexts = g_tabtexts + SEP }
    g_tabtexts = g_tabtexts + text
    emit "1"
}

// ── tabs ──────────────────────────────────────────────────────────────

func saveCurTab() {
    if g_curtab < 0 { emit "1" }
    tabTextSet(g_curtab, guiGetText(g_editor))
    emit "1"
}

func rebuildTabs() {
    // Clear + re-add all tabs from g_tabpaths.
    // gui.k's tab API: guiTabAdd appends. There's no clear, so we just
    // append the labels that aren't there yet (rebuildTabs is only called
    // after openTab anyway, which adds one).
    let want = nlines(g_tabpaths) + 1
    let have = guiTabSelected(g_tabs) + 1   // crude: we trust last-added count
    let i = have
    while i < want {
        guiTabAdd(g_tabs, baseName(lineAt(g_tabpaths, i)))
        i = i + 1
    }
    emit "1"
}

func selectTab(idx) {
    guiTabSelect(g_tabs, idx)
    guiSetText(g_editor, tabTextAt(idx))
    g_curtab = idx
    let path = lineAt(g_tabpaths, idx)
    if len(path) > 0 {
        // SetWindowTextA on the main window changes the title bar.
        guiSetText(g_win, "brain — " + path)
    }
    emit "1"
}

func openTab(path) {
    saveCurTab()
    // Already-open?
    let count = nlines(g_tabpaths) + 1
    if len(g_tabpaths) == 0 { count = 0 }
    let i = 0  let found = 0 - 1
    while i < count {
        if lineAt(g_tabpaths, i) == path { found = i }
        i = i + 1
    }
    if found < 0 {
        if len(g_tabpaths) > 0 { g_tabpaths = g_tabpaths + "\n" }
        g_tabpaths = g_tabpaths + path
        tabTextAdd(readFile(path))
        found = count
    }
    rebuildTabs()
    selectTab(found)
    emit "1"
}

func onTabChange() {
    saveCurTab()
    selectTab(guiTabSelected(g_tabs))
}

// ── menu / button actions ─────────────────────────────────────────────

func onRun() {
    if g_curtab < 0 {
        guiMessageBox("Run", "Open a .k file first.")
        emit "1"
    }
    let path = lineAt(g_tabpaths, g_curtab)
    saveCurTab()
    writeFile(path, guiGetText(g_editor))
    let cmd = "cd " + g_dir + " && kcc " + path + " -o brainrun.exe 2>&1 && brainrun.exe 2>&1"
    let out = exec(cmd)
    appendConsole("$ run " + baseName(path) + "\n" + out + "\n")
}

func onOpen() {
    let path = guiOpenFile("Open .k file", "Krypton scripts|*.k;*.ks|All files|*.*")
    if len(path) > 0 { openTab(path) }
}

func onSave() {
    if g_curtab < 0 { emit "1" }
    let path = lineAt(g_tabpaths, g_curtab)
    saveCurTab()
    writeFile(path, guiGetText(g_editor))
    appendConsole("$ saved " + baseName(path) + "\n")
}

func onTreeClick() {
    let idx = guiListSelected(g_tree)
    if idx < 0 { emit "1" }
    let fname = lineAt(g_files, idx)
    if len(fname) > 0 { openTab(g_dir + "/" + fname) }
}

// ── integrated console (stem v0.1 equivalent) ─────────────────────────

func appendConsole(s) {
    let cur = guiGetText(g_console)
    guiSetText(g_console, cur + s)
    emit "1"
}

func onCmd() {
    let line = guiGetText(g_cmdline)
    if len(line) == 0 { emit "1" }
    let out = exec("cd " + g_dir + " && " + line + " 2>&1")
    appendConsole("$ " + line + "\n" + out + "\n")
    guiSetText(g_cmdline, "")
}

// ── app entry ─────────────────────────────────────────────────────────

just run {
    g_dir = arg(0)
    if len(g_dir) == 0 { g_dir = "." }
    g_files = exec("cmd /c dir /b " + g_dir)   // \n-separated filenames

    guiInit()
    g_win = guiWindow("brain — pure-Krypton IDE", 1100, 700)

    // Layout: file tree (left, 0..240), tabs+editor (240..1100 top),
    // console (full width, bottom 160px), cmdline (under console, 24px).
    g_tree    = guiListbox(g_win,   0,   0,  240, 540)
    g_tabs    = guiTabs(g_win,    240,   0,  860,  24)
    g_editor  = guiRichEdit(g_win, 240,  24,  860, 516)
    g_console = guiRichEdit(g_win,   0, 540, 1100, 130)
    g_cmdline = guiTextInput(g_win,  0, 670, 1100,  24)

    guiRichSetMonoFont(g_editor,  "Cascadia Mono", 12)
    guiRichSetMonoFont(g_console, "Cascadia Mono", 11)
    guiRichReadOnly(g_console, 1)

    // Populate file tree.
    let n = nlines(g_files)
    let i = 0
    while i < n {
        let fn = lineAt(g_files, i)
        if len(fn) > 0 { guiListAdd(g_tree, fn) }
        i = i + 1
    }

    // Wire events.
    guiOnChange(g_tree, funcptr(onTreeClick))
    guiOnChange(g_tabs, funcptr(onTabChange))
    guiOnClick(g_cmdline, funcptr(onCmd))   // Enter-press on text input

    // Menu bar (File / Run).
    let bar  = guiMenuBegin(g_win)
    let file = guiMenu(bar, "File")
    guiMenuAdd(file, "Open\tCtrl+O")
    guiMenuAdd(file, "Save\tCtrl+S")
    guiMenuSeparator(file)
    guiMenuAdd(file, "Exit")
    let run  = guiMenu(bar, "Run")
    guiMenuAdd(run, "Run current\tCtrl+R")

    guiSetText(g_editor, "// brain — pure-Krypton IDE on Windows. click a file on the left.\n")
    guiSetText(g_console, "stem — integrated terminal. type a command, press Enter.\n")

    guiShow(g_win)
    guiRun()
}
