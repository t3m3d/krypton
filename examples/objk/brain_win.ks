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
import "head:windows"

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

// ── syntax highlighting (Krypton + KryptScript flavour) ───────────────
// Linear scan: comments (//... \n) → strings ("...") → keywords →
// numbers. For each token type, paint via guiRichSetFmt(start, end,
// color, bold). Re-runs on every guiOnChange — debouncing isn't worth
// the complexity at this code volume.

func _isAlpha(c) {
    let code = charCode(c)
    if code >= 65 { if code <=  90 { emit "1" } }
    if code >= 97 { if code <= 122 { emit "1" } }
    if c == "_" { emit "1" }
    emit ""
}
func _isAlnum(c) {
    if _isAlpha(c) == "1" { emit "1" }
    let code = charCode(c)
    if code >= 48 { if code <= 57 { emit "1" } }
    emit ""
}
func _isDigit(c) {
    let code = charCode(c)
    if code >= 48 { if code <= 57 { emit "1" } }
    emit ""
}

func _isKeyword(w) {
    if w == "func"   { emit "1" }
    if w == "let"    { emit "1" }
    if w == "if"     { emit "1" }
    if w == "else"   { emit "1" }
    if w == "while"  { emit "1" }
    if w == "for"    { emit "1" }
    if w == "in"     { emit "1" }
    if w == "emit"   { emit "1" }
    if w == "return" { emit "1" }
    if w == "just"   { emit "1" }
    if w == "run"    { emit "1" }
    if w == "import" { emit "1" }
    if w == "module" { emit "1" }
    if w == "jxt"    { emit "1" }
    if w == "struct" { emit "1" }
    if w == "field"  { emit "1" }
    if w == "break"  { emit "1" }
    if w == "true"   { emit "1" }
    if w == "false"  { emit "1" }
    emit ""
}

let g_hlBusy = 0   // re-entry guard — guiRichSetFmt may itself fire EN_CHANGE

func highlightEditor() {
    if g_hlBusy == 1 { emit "1" }
    g_hlBusy = 1
    let src = guiGetText(g_editor)
    let n = len(src)
    // Reset any prior colouring on the whole document. guiRichClearFmt
    // applies to the current selection, so we'd need to select all first;
    // it's simpler to repaint EVERY token below and accept that any cell
    // not painted as a token stays default (cleared each frame by the
    // overlapping per-token writes).
    guiRichSetFmt(g_editor, "0", n + "", "e8e8e8", "0")
    let i = 0
    while i < n {
        let c = src[i]
        // line comment "// ... \n"
        if c == "/" {
            if i + 1 < n {
                if src[i + 1] == "/" {
                    let end = i
                    let done = 0
                    while end < n {
                        if src[end] == "\n" { done = 1  end = n + 1000 }
                        else                { end = end + 1 }
                    }
                    if end >= n + 1000 { end = end - 1000 }
                    guiRichSetFmt(g_editor, i + "", end + "", "6a9955", "0")
                    i = end
                }
            }
        }
        if i >= n { i = n }
        let cc = src[i]
        // string literal "..." with simple backslash escape skip
        if cc == "\"" {
            let end = i + 1
            let closed = 0
            while end < n {
                let ch = src[end]
                if ch == "\\" { end = end + 2 }
                else {
                    if ch == "\"" { closed = 1  end = end + 1  let stop = n + 1000  end = stop }
                    else          { end = end + 1 }
                }
            }
            if end >= n + 1000 { end = end - 1000 }
            guiRichSetFmt(g_editor, i + "", end + "", "ce9178", "0")
            i = end
        }
        if i >= n { i = n }
        let dd = src[i]
        // number (run of digits)
        if _isDigit(dd) == "1" {
            let end = i + 1
            while end < n {
                if _isDigit(src[end]) == "1" { end = end + 1 }
                else                          { end = n + 1000 }
            }
            if end >= n + 1000 { end = end - 1000 }
            guiRichSetFmt(g_editor, i + "", end + "", "b5cea8", "0")
            i = end
        }
        if i >= n { i = n }
        let ee = src[i]
        // identifier / keyword
        if _isAlpha(ee) == "1" {
            let end = i + 1
            while end < n {
                if _isAlnum(src[end]) == "1" { end = end + 1 }
                else                          { end = n + 1000 }
            }
            if end >= n + 1000 { end = end - 1000 }
            let word = substring(src, i, end)
            if _isKeyword(word) == "1" {
                guiRichSetFmt(g_editor, i + "", end + "", "c586c0", "1")
            }
            i = end
        }
        if i < n { i = i + 1 }
    }
    g_hlBusy = 0
    emit "1"
}

// ── integrated console (live "stem" pane) ────────────────────────────
// Lifted from stem_win.ks v0.1.2: ANSI colour rendering via guiRichAppend,
// cwd persistence across commands, clear/cls/exit builtins. Per-command
// exec() (not ConPTY-interactive yet — that's stem_win_pty in progress).

let g_consoleCwd = ""
let g_curFg      = ""
let g_curBold    = 0

func _sgrBaseColor(n) {
    if n == 30 { emit "1e1e1e" }
    if n == 31 { emit "f14c4c" }
    if n == 32 { emit "23d18b" }
    if n == 33 { emit "f5f543" }
    if n == 34 { emit "3b8eea" }
    if n == 35 { emit "d670d6" }
    if n == 36 { emit "29b8db" }
    if n == 37 { emit "e5e5e5" }
    if n == 90 { emit "666666" }
    if n == 91 { emit "f14c4c" }
    if n == 92 { emit "23d18b" }
    if n == 93 { emit "f5f543" }
    if n == 94 { emit "3b8eea" }
    if n == 95 { emit "d670d6" }
    if n == 96 { emit "29b8db" }
    if n == 97 { emit "ffffff" }
    emit ""
}
func _hex2(n) {
    let H = "0123456789abcdef"
    let hi = n / 16
    let lo = n - hi * 16
    emit substring(H, hi, hi + 1) + substring(H, lo, lo + 1)
}
func _intAt(p, i) {
    let n = len(p)  let start = i
    while i < n { if p[i] == ";" { emit substring(p, start, i) }  i = i + 1 }
    emit substring(p, start, n)
}
func _afterSemi(p, i) {
    let n = len(p)
    while i < n { if p[i] == ";" { emit i + 1 }  i = i + 1 }
    emit n
}
func _applySgr(params) {
    if len(params) == 0 { g_curFg = ""  g_curBold = 0  emit "1" }
    let n = len(params)
    let i = 0
    while i < n {
        let code = toInt(_intAt(params, i))
        if code == 0  { g_curFg = ""  g_curBold = 0 }
        if code == 1  { g_curBold = 1 }
        if code == 22 { g_curBold = 0 }
        if code == 39 { g_curFg = "" }
        if code >= 30 { if code <= 37 { g_curFg = _sgrBaseColor(code) } }
        if code >= 90 { if code <= 97 { g_curFg = _sgrBaseColor(code) } }
        if code == 38 {
            let j = _afterSemi(params, i)
            if j < n {
                if toInt(_intAt(params, j)) == 2 {
                    let j1 = _afterSemi(params, j)
                    let r = toInt(_intAt(params, j1))
                    let j2 = _afterSemi(params, j1)
                    let g = toInt(_intAt(params, j2))
                    let j3 = _afterSemi(params, j2)
                    let b = toInt(_intAt(params, j3))
                    g_curFg = _hex2(r) + _hex2(g) + _hex2(b)
                    i = _afterSemi(params, j3) - 1
                }
            }
        }
        i = _afterSemi(params, i)
    }
    emit "1"
}
func _consumeCSI(s, start) {
    let n = len(s)  let i = start  let params = ""
    while i < n {
        let cc = s[i]  let code = charCode(cc)
        if code >= 64 { if code <= 126 {
            if cc == "m" { _applySgr(params) }
            emit i + 1
        } }
        params = params + cc
        i = i + 1
    }
    emit n
}
func _consumeOther(s, start) {
    let n = len(s)  let i = start
    while i < n {
        let cc = s[i]  let code = charCode(cc)
        if cc == fromCharCode(7) { emit i + 1 }
        if code >= 64 { if code <= 126 { emit i + 1 } }
        i = i + 1
    }
    emit n
}
func appendConsole(s) {
    let n = len(s)  let buf = ""  let i = 0
    let ESC = fromCharCode(27)
    while i < n {
        let c = s[i]
        if c != ESC {
            buf = buf + c
            i = i + 1
        } else {
            if len(buf) > 0 { guiRichAppend(g_console, buf, g_curFg, g_curBold)  buf = "" }
            i = i + 1
            if i < n {
                let kind = s[i]
                i = i + 1
                if kind == "[" { i = _consumeCSI(s, i) }
                else          { i = _consumeOther(s, i) }
            }
        }
    }
    if len(buf) > 0 { guiRichAppend(g_console, buf, g_curFg, g_curBold) }
    emit "1"
}

// Local `cd <path>` so directory changes persist across the per-command
// exec()s. Matches stem_win's parser.
func _parseCd(line) {
    let n = len(line)  let i = 0
    while i < n { if line[i] != " " { i = n + 1 }  i = i + 1 }
    let start = i - 1
    if start < 0 { emit "" }
    if start + 3 > n { emit "" }
    if substring(line, start, start + 3) != "cd " { emit "" }
    let arg = substring(line, start + 3, n)
    let e = len(arg)
    while e > 0 {
        if arg[e - 1] != " " { emit substring(arg, 0, e) }
        e = e - 1
    }
    emit ""
}
func _resolveCd(target) {
    if len(target) == 0 { emit g_consoleCwd }
    if len(target) >= 2 { if target[1] == ":" { emit target } }
    if target[0] == "\\" { emit target }
    if target[0] == "/"  { emit target }
    if target == ".." {
        let n = len(g_consoleCwd)  let i = n - 1
        while i >= 0 {
            if g_consoleCwd[i] == "\\" { emit substring(g_consoleCwd, 0, i) }
            if g_consoleCwd[i] == "/"  { emit substring(g_consoleCwd, 0, i) }
            i = i - 1
        }
        emit g_consoleCwd
    }
    emit g_consoleCwd + "\\" + target
}

func onCmd() {
    let line = guiGetText(g_cmdline)
    if len(line) == 0 { emit "1" }
    guiSetText(g_cmdline, "")

    // builtins
    if line == "clear" { guiSetText(g_console, "")  emit "1" }
    if line == "cls"   { guiSetText(g_console, "")  emit "1" }
    if line == "exit"  { ExitProcess("0") }

    // local cd
    let cdTarget = _parseCd(line)
    if len(cdTarget) > 0 {
        g_consoleCwd = _resolveCd(cdTarget)
        appendConsole("$ " + line + "\n")
        emit "1"
    }

    let out = exec("cd /d " + g_consoleCwd + " && " + line + " 2>&1")
    appendConsole("$ " + line + "\n" + out + "\n")
    emit "1"
}

// ── app entry ─────────────────────────────────────────────────────────

just run {
    g_dir = arg(0)
    if len(g_dir) == 0 { g_dir = "." }
    g_consoleCwd = g_dir   // console starts in the project dir
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
    // Make the console pane visually a terminal — dark bg + off-white fg,
    // same palette as stem_win so the two read as the same kind of thing.
    guiRichSetBg(g_console, "0a0a0a")
    guiRichSetFgDefault(g_console, "e8e8e8")
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
    guiOnChange(g_editor, funcptr(highlightEditor))   // re-tokenise on edit

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
    // Console boot: a couple priming lines so the pane reads as live.
    appendConsole("\x1b[36mstem\x1b[0m — integrated terminal in brain.\n")
    appendConsole("type a command + Enter. builtins: clear, cls, exit.\n")
    appendConsole("\x1b[90mcwd: " + g_consoleCwd + "\x1b[0m\n\n")
    // Self-test: run a tagged echo so we can visually confirm the live-stem
    // pipeline (exec → ANSI render → guiRichAppend) end-to-end on every launch.
    let selftest = exec("cd /d " + g_consoleCwd + " && echo selftest OK 2>&1")
    appendConsole("\x1b[33m$ echo selftest OK\x1b[0m\n")
    appendConsole(selftest + "\n")

    guiShow(g_win)
    guiRun()
}
