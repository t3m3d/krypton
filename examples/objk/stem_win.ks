// stem_win.ks -- Windows port of stem, the terminal that pairs with brain.
//
// v0.1.3 -- rewritten on guiStateSet/Get because module-level mutable
// lets read garbage across function boundaries (the
// feedback_module_mutable_globals.md flake).  All widget handles and
// mutable state live in the gui state table.  Colours are 0x-prefixed
// per gui.k's _guiHexToInt contract.
//
// Build:  kcc.exe examples/objk/stem_win.ks -o stem.exe
// Then patch PE subsystem CUI→GUI to suppress the console window.
//
// Pair / lineage:
//   examples/objk/brain_win.ks  -- IDE with stem inside its console pane
//   examples/objk/brain.ks      -- macOS sibling (Cocoa)
//   examples/objk/stem_win_pty.ks -- v0.2 ConPTY spike (parked)

import "k:gui"
import "head:windows"

// ── state accessors (workaround for module-mutable-globals) ──────────

func _o()       { emit guiStateGet("stem.output") }
func _ci()      { emit guiStateGet("stem.cmdline") }
func _wh()      { emit guiStateGet("stem.win") }
func _cwdG()    { emit guiStateGet("stem.cwd") }
func _cwdS(v)   { guiStateSet("stem.cwd", v)  emit "1" }
func _fgG()     { emit guiStateGet("stem.curFg") }
func _fgS(v)    { guiStateSet("stem.curFg", v)  emit "1" }
func _boldGet() { if guiStateGet("stem.curBold") == "1" { emit "1" }  emit "0" }
func _boldSet1() { guiStateSet("stem.curBold", "1")  emit "1" }
func _boldSet0() { guiStateSet("stem.curBold", "0")  emit "1" }

// ── theme detection ──────────────────────────────────────────────────

func regReadDword(path, name) {
    let HKCU = "2147483649"
    let kread = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKCU, path, "0", kread, phResult)
    if r != "0" { emit "" }
    let hk = bufGetQword(phResult)
    let buf = bufNew("4")
    let sz  = bufNew("4")
    bufSetDword(sz, "4")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufGetDword(buf)
}
func osIsLightMode() {
    let v = regReadDword("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                         "AppsUseLightTheme")
    if v == "" { emit "1" }
    if v == "1" { emit "1" }
    emit "0"
}

// ── ANSI colour rendering ────────────────────────────────────────────

func sgrBaseColor(n) {
    if n == 30 { emit "0x1e1e1e" }
    if n == 31 { emit "0xf14c4c" }
    if n == 32 { emit "0x23d18b" }
    if n == 33 { emit "0xf5f543" }
    if n == 34 { emit "0x3b8eea" }
    if n == 35 { emit "0xd670d6" }
    if n == 36 { emit "0x29b8db" }
    if n == 37 { emit "0xe5e5e5" }
    if n == 90 { emit "0x666666" }
    if n == 91 { emit "0xf14c4c" }
    if n == 92 { emit "0x23d18b" }
    if n == 93 { emit "0xf5f543" }
    if n == 94 { emit "0x3b8eea" }
    if n == 95 { emit "0xd670d6" }
    if n == 96 { emit "0x29b8db" }
    if n == 97 { emit "0xffffff" }
    emit ""
}
func _hex2(n) {
    let H = "0123456789abcdef"
    let hi = n / 16
    let lo = n - hi * 16
    emit substring(H, hi, hi + 1) + substring(H, lo, lo + 1)
}
func _rgbHex(r, g, b) { emit "0x" + _hex2(r) + _hex2(g) + _hex2(b) }

func _intAt(params, i) {
    let n = len(params)  let start = i
    while i < n { if params[i] == ";" { emit substring(params, start, i) }  i = i + 1 }
    emit substring(params, start, n)
}
func _afterSemi(params, i) {
    let n = len(params)
    while i < n { if params[i] == ";" { emit i + 1 }  i = i + 1 }
    emit n
}

func applySgr(params) {
    if len(params) == 0 { _fgS("")  _boldSet0()  emit "1" }
    let n = len(params)
    let i = 0
    while i < n {
        let code = toInt(_intAt(params, i))
        if code == 0  { _fgS("")  _boldSet0() }
        if code == 1  { _boldSet1() }
        if code == 22 { _boldSet0() }
        if code == 39 { _fgS("") }
        if code >= 30 { if code <= 37 { _fgS(sgrBaseColor(code)) } }
        if code >= 90 { if code <= 97 { _fgS(sgrBaseColor(code)) } }
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
                    _fgS(_rgbHex(r, g, b))
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
            if cc == "m" { applySgr(params) }
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
// guiRichAppend resolves "" to COLORREF 0 = black, invisible on dark
// bg.  Substitute the theme default when curFg blank.
func _fgOrDefault() {
    let f = _fgG()
    if len(f) == 0 { emit "0xe8e8e8" }
    emit f
}
func appendOutput(s) {
    let n = len(s)
    let buf = ""
    let i = 0
    let ESC = fromCharCode(27)
    while i < n {
        let c = s[i]
        if c != ESC {
            buf = buf + c
            i = i + 1
        } else {
            if len(buf) > 0 {
                guiRichAppend(_o(), buf, _fgOrDefault(), _boldGet())
                buf = ""
            }
            i = i + 1
            if i < n {
                let kind = s[i]
                i = i + 1
                if kind == "[" { i = _consumeCSI(s, i) }
                else          { i = _consumeOther(s, i) }
            }
        }
    }
    if len(buf) > 0 {
        guiRichAppend(_o(), buf, _fgOrDefault(), _boldGet())
    }
    emit "1"
}

// ── title bar shows cwd ──────────────────────────────────────────────

func refreshTitle() {
    guiSetText(_wh(), "stem -- " + _cwdG())
    emit "1"
}

// ── cwd persistence across exec() ────────────────────────────────────

func _parseCd(line) {
    let n = len(line)  let i = 0
    while i < n { if line[i] != " " { i = n + 1 }  i = i + 1 }
    let start = i - 1
    if start < 0 { emit "" }
    if start + 3 > n { emit "" }
    if substring(line, start, start + 3) != "cd " { emit "" }
    let arg = substring(line, start + 3, n)
    let e = len(arg)
    while e > 0 { if arg[e - 1] != " " { emit substring(arg, 0, e) }  e = e - 1 }
    emit ""
}
func _resolveCd(target) {
    let cwd = _cwdG()
    if len(target) == 0 { emit cwd }
    if len(target) >= 2 { if target[1] == ":" { emit target } }
    if target[0] == "\\" { emit target }
    if target[0] == "/"  { emit target }
    if target == ".." {
        let n = len(cwd)  let i = n - 1
        while i >= 0 {
            if cwd[i] == "\\" { emit substring(cwd, 0, i) }
            if cwd[i] == "/"  { emit substring(cwd, 0, i) }
            i = i - 1
        }
        emit cwd
    }
    emit cwd + "\\" + target
}

func runCommand(line) {
    let cdTarget = _parseCd(line)
    if len(cdTarget) > 0 {
        _cwdS(_resolveCd(cdTarget))
        appendOutput("$ " + line + "\n")
        refreshTitle()
        emit "1"
    }
    let full = "cd /d " + _cwdG() + " && " + line + " 2>&1"
    let out = exec(full)
    appendOutput("$ " + line + "\n" + out + "\n")
    emit "1"
}

func _isWs(c) {
    if c == " "  { emit "1" }
    if c == "\t" { emit "1" }
    if c == "\r" { emit "1" }
    if c == "\n" { emit "1" }
    emit ""
}
func trimSpaces(s) {
    let n = len(s)
    let a = 0
    while a < n {
        if _isWs(s[a]) == "1" { a = a + 1 }
        else {
            let b = n
            while b > a {
                if _isWs(s[b - 1]) == "1" { b = b - 1 }
                else { emit substring(s, a, b) }
            }
            emit ""
        }
    }
    emit ""
}

func tryBuiltin(line) {
    let l = trimSpaces(line)
    if l == "clear" {
        guiSetText(_o(), "")
        guiSetText(_ci(), "")
        emit "1"
    }
    if l == "cls" {
        guiSetText(_o(), "")
        guiSetText(_ci(), "")
        emit "1"
    }
    if l == "exit" { ExitProcess("0")  emit "1" }
    emit ""
}

func onCmd() {
    let line = guiGetText(_ci())
    if len(line) == 0 { emit "1" }
    if tryBuiltin(line) == "1" { emit "1" }
    runCommand(line)
    guiSetText(_ci(), "")
}

// ── entry ────────────────────────────────────────────────────────────

just run {
    let cwd = arg(0)
    if len(cwd) == 0 {
        cwd = exec("cmd /c echo %USERPROFILE%")
        let nlen = len(cwd)
        while nlen > 0 {
            let lc = nlen - 1
            if cwd[lc] != "\n" {
                if cwd[lc] != "\r" { cwd = substring(cwd, 0, nlen)  nlen = 0 - 1 }
            }
            nlen = nlen - 1
        }
    }
    _cwdS(cwd)
    _fgS("")
    _boldSet0()

    let bg = "0x2d2d2d"
    if osIsLightMode() == "0" { bg = "0x0a0a0a" }
    let fg = "0xe8e8e8"
    guiSetWindowBg(bg)

    guiInit()
    let win = guiWindow("stem", 900, 600)
    guiStateSet("stem.win", win + "")

    let output  = guiRichEdit(win,  0,   0, 900, 560)
    let cmdline = guiTextInput(win, 0, 560, 900,  40)
    guiStateSet("stem.output",  output + "")
    guiStateSet("stem.cmdline", cmdline + "")

    guiRichSetMonoFont(output, "Cascadia Mono", 11)
    guiRichSetBg(output, bg)
    guiRichSetFgDefault(output, fg)
    guiRichReadOnly(output, 1)
    guiOnClick(cmdline, funcptr(onCmd))

    refreshTitle()
    appendOutput("\x1b[36mstem v0.1.3\x1b[0m -- pure-Krypton terminal (objk/Win32).\n")
    appendOutput("builtins: clear / cls / exit. cd persists across commands.\n")
    appendOutput("ANSI colours render inline via guiRichAppend.\n")
    appendOutput("\x1b[90mcwd: " + cwd + "\x1b[0m\n\n")

    guiShow(win)
    guiRun()
}
