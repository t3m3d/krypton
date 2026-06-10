// stem_win_pty.ks — v0.2 of stem (Windows). Interactive ConPTY shell.
//
// Spawns one long-lived cmd.exe (or whatever shell is on PATH) attached
// to a Windows pseudoconsole. The shell's stdout is read async via
// guiSetTimer + PeekNamedPipe + ReadFile; the cmdline input WriteFiles
// straight to the shell's stdin so env, cwd, history all persist
// inside the running shell (no more "fresh cmd per Enter" trick).
//
// Build:
//   kcc.exe examples/objk/stem_win_pty.ks -o stem.exe
//
// Lineage:
//   stem_win.ks      — v0.1.2 command runner (exec() per Enter, ANSI colour)
//   stem_win_pty.ks  — THIS, v0.2 persistent ConPTY shell
//
// Caveats:
//   - Single shell process. Detect exit → close window.
//   - No keystroke-pass-through yet (still line-by-line via cmdline);
//     true interactive (Ctrl-C, Tab completion, vim) needs key-event
//     forwarding which gui.k doesn't expose. v0.3.
//   - No resize: terminal stays at the initial cols/rows we asked for.

import "k:gui"
import "head:windows"
import "head:fileio"

// ── module state ──────────────────────────────────────────────────────

let g_win       = 0
let g_output    = 0
let g_cmdline   = 0

let g_hPC       = "0"        // HPCON handle
let g_inWrite   = "0"        // our writable end of the input pipe (→ shell stdin)
let g_outRead   = "0"        // our readable end of the output pipe (← shell stdout)
let g_hProc     = "0"        // shell process handle
let g_alive     = 0

let g_curFg     = ""
let g_curBold   = 0

// ── ANSI colour rendering (carried over from v0.1.2) ──────────────────

func sgrBaseColor(n) {
    if n == 30 { emit "0x1e1e1e" }
    if n == 31 { emit "0xf14c4c" }
    if n == 32 { emit "0x23d18b" }
    if n == 33 { emit "0xf5f543" }
    if n == 34 { emit "0x3b8eea" }
    if n == 35 { emit "0xd670d6" }
    if n == 36 { emit "0x29b8db" }
    if n == 37 { emit "0xe5e5e5" }
    if n == 90 { emit "666666" }
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
func _rgbHex(r, g, b) { emit _hex2(r) + _hex2(g) + _hex2(b) }

func _intAt(params, i) {
    let n = len(params)
    let start = i
    while i < n { if params[i] == ";" { emit substring(params, start, i) }  i = i + 1 }
    emit substring(params, start, n)
}
func _afterSemi(params, i) {
    let n = len(params)
    while i < n { if params[i] == ";" { emit i + 1 }  i = i + 1 }
    emit n
}

func applySgr(params) {
    if len(params) == 0 { g_curFg = ""  g_curBold = 0  emit "1" }
    let n = len(params)
    let i = 0
    while i < n {
        let code = toInt(_intAt(params, i))
        if code == 0  { g_curFg = ""  g_curBold = 0 }
        if code == 1  { g_curBold = 1 }
        if code == 22 { g_curBold = 0 }
        if code == 39 { g_curFg = "" }
        if code >= 30 { if code <= 37 { g_curFg = sgrBaseColor(code) } }
        if code >= 90 { if code <= 97 { g_curFg = sgrBaseColor(code) } }
        if code == 38 {
            let j = _afterSemi(params, i)
            if j < n {
                let mode = toInt(_intAt(params, j))
                if mode == 2 {
                    let j1 = _afterSemi(params, j)
                    let r = toInt(_intAt(params, j1))
                    let j2 = _afterSemi(params, j1)
                    let g = toInt(_intAt(params, j2))
                    let j3 = _afterSemi(params, j2)
                    let b = toInt(_intAt(params, j3))
                    g_curFg = _rgbHex(r, g, b)
                    i = _afterSemi(params, j3) - 1
                }
            }
        }
        i = _afterSemi(params, i)
    }
    emit "1"
}

func _consumeCSI(s, start) {
    let n = len(s)
    let i = start
    let params = ""
    while i < n {
        let cc = s[i]
        let code = charCode(cc)
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
    let n = len(s)
    let i = start
    while i < n {
        let cc = s[i]
        let code = charCode(cc)
        if cc == fromCharCode(7) { emit i + 1 }
        if code >= 64 { if code <= 126 { emit i + 1 } }
        i = i + 1
    }
    emit n
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
            if len(buf) > 0 { guiRichAppend(g_output, buf, g_curFg, g_curBold)  buf = "" }
            i = i + 1
            if i < n {
                let kind = s[i]
                i = i + 1
                if kind == "[" { i = _consumeCSI(s, i) }
                else          { i = _consumeOther(s, i) }
            }
        }
    }
    if len(buf) > 0 { guiRichAppend(g_output, buf, g_curFg, g_curBold) }
    emit "1"
}

// ── ConPTY setup ──────────────────────────────────────────────────────

// COORD is packed into an int (low16=cols, high16=rows) per the
// CreatePseudoConsole binding's marshalling table (headers/windows.krh:269).
func _packCoord(cols, rows) { emit cols + rows * 65536 }

// Create the pseudoconsole + spawn cmd.exe attached to it. Sets g_hPC,
// g_inWrite, g_outRead, g_hProc and g_alive on success. Returns "1" on
// success, "" on any failure (caller falls back to non-interactive mode).
func ptySpawn(cmd, cols, rows) {
    appendOutput("[isolation] entering ptySpawn\n")
    appendOutput("[isolation] returning early to confirm window survives\n")
    emit ""    // bail before any Win32 calls
    appendOutput("[ptySpawn] step 1: SECURITY_ATTRIBUTES\n")
    let SA  = bufNew("24")
    bufSetDword(SA, "24")              // nLength = 24
    bufSetQwordAt(SA, "8",  "0")        // lpSecurityDescriptor = NULL
    bufSetDwordAt(SA, "16", "1")       // bInheritHandle = TRUE

    appendOutput("[ptySpawn] step 2: CreatePipe x2\n")
    let inR = bufNew(8)
    let inW = bufNew(8)
    if CreatePipe(inR, inW, SA, "0") == "0" {
        appendOutput("[ptySpawn] CreatePipe(input) failed\n")
        emit ""
    }
    let outR = bufNew(8)
    let outW = bufNew(8)
    if CreatePipe(outR, outW, SA, "0") == "0" {
        appendOutput("[ptySpawn] CreatePipe(output) failed\n")
        CloseHandle(bufGetQword(inR))  CloseHandle(bufGetQword(inW))
        emit ""
    }

    let hInR  = bufGetQword(inR)
    let hInW  = bufGetQword(inW)
    let hOutR = bufGetQword(outR)
    let hOutW = bufGetQword(outW)
    appendOutput("[ptySpawn] step 3: CreatePseudoConsole\n")

    let hPCBuf = bufNew(8)
    let size = _packCoord(cols, rows)
    let hr = CreatePseudoConsole(size + "", hInR + "", hOutW + "", "0", hPCBuf)
    CloseHandle(hInR + "")
    CloseHandle(hOutW + "")
    if hr != "0" {
        appendOutput("[ptySpawn] CreatePseudoConsole hr=" + hr + "\n")
        CloseHandle(hInW + "")  CloseHandle(hOutR + "")
        emit ""
    }
    let hPC = bufGetQword(hPCBuf)

    appendOutput("[ptySpawn] step 4: attribute list size probe\n")
    let sizeBuf = bufNew(8)
    bufSetQword(sizeBuf, "0")
    InitializeProcThreadAttributeList(toHandle("0"), "1", "0", sizeBuf)
    let attrSize = toInt(bufGetQword(sizeBuf))
    if attrSize == 0 {
        appendOutput("[ptySpawn] attrSize is 0\n")
        ClosePseudoConsole(hPC + "")  CloseHandle(hInW + "")  CloseHandle(hOutR + "")
        emit ""
    }
    appendOutput("[ptySpawn] step 5: InitializeProcThreadAttributeList\n")
    let attrs = bufNew(attrSize + "")
    bufSetQword(sizeBuf, attrSize + "")
    if InitializeProcThreadAttributeList(attrs, "1", "0", sizeBuf) == "0" {
        appendOutput("[ptySpawn] Initialize failed\n")
        ClosePseudoConsole(hPC + "")  CloseHandle(hInW + "")  CloseHandle(hOutR + "")
        emit ""
    }
    appendOutput("[ptySpawn] step 6: UpdateProcThreadAttribute\n")
    let hPCBox = bufNew(8)
    bufSetQword(hPCBox, hPC + "")
    if UpdateProcThreadAttribute(attrs, "0", "131094", hPCBox, "8",
                                  toHandle("0"), toHandle("0")) == "0" {
        appendOutput("[ptySpawn] UpdateProcThreadAttribute failed\n")
        DeleteProcThreadAttributeList(attrs)
        ClosePseudoConsole(hPC + "")  CloseHandle(hInW + "")  CloseHandle(hOutR + "")
        emit ""
    }

    appendOutput("[ptySpawn] step 7: STARTUPINFOEX + CreateProcessA\n")
    let si = bufNew(112)
    bufSetDword(si, "112")
    bufSetQwordAt(si, "104", ptrToInt(attrs) + "")
    let pi = bufNew(24)
    let cmdBuf = bufNew(len(cmd) + 1)
    let ci = 0
    while ci < len(cmd) { bufSetByte(cmdBuf, ci, charCode(cmd[ci]))  ci = ci + 1 }
    bufSetByte(cmdBuf, len(cmd), 0)

    if CreateProcessA(toHandle("0"), cmdBuf, toHandle("0"), toHandle("0"),
                      "0", "524288", toHandle("0"), toHandle("0"),
                      si, pi) == "0" {
        appendOutput("[ptySpawn] CreateProcessA failed\n")
        DeleteProcThreadAttributeList(attrs)
        ClosePseudoConsole(hPC + "")  CloseHandle(hInW + "")  CloseHandle(hOutR + "")
        emit ""
    }

    appendOutput("[ptySpawn] step 8: handle plumbing done — shell is live\n")
    g_hPC     = hPC + ""
    g_inWrite = hInW + ""
    g_outRead = hOutR + ""
    g_hProc   = bufGetQword(pi) + ""
    g_alive   = 1
    emit "1"
}

// ── async output drain ────────────────────────────────────────────────

let g_readBuf = 0     // bufNew(4096), reused across ticks
let g_avail   = 0     // bufNew(4) — PeekNamedPipe totalAvail
let g_read    = 0     // bufNew(4) — actual bytes read

func ptyDrainOnce() {
    if g_alive != 1 { emit "1" }
    PeekNamedPipe(g_outRead, toHandle("0"), "0",
                  toHandle("0"), g_avail, toHandle("0"))
    let avail = toInt(bufGetDword(g_avail))
    if avail == 0 { emit "1" }
    let want = avail
    if want > 4096 { want = 4096 }
    if ReadFile(g_outRead, g_readBuf, want + "", g_read, toHandle("0")) == "0" {
        emit "1"
    }
    let got = toInt(bufGetDword(g_read))
    if got > 0 {
        // Slurp into a Krypton string. bufStr stops at the first NUL —
        // ConPTY output is text, so we trust that; if NULs were a real
        // concern we'd loop byte-by-byte.
        let chunk = ""
        let bi = 0
        while bi < got {
            chunk = chunk + fromCharCode(bufGetByte(g_readBuf, bi))
            bi = bi + 1
        }
        appendOutput(chunk)
    }
    emit "1"
}

// ── input ─────────────────────────────────────────────────────────────

func ptyWrite(s) {
    if g_alive != 1 { emit "" }
    let nb = bufNew(8)
    WriteFile(g_inWrite, s, len(s) + "", nb, toHandle("0"))
    emit ""
}

// Builtin commands. clear/cls is now ambiguous — the shell has its own.
// We just forward and let the shell paint; only 'exit' we intercept to
// terminate the process cleanly.
func tryBuiltin(line) {
    let t = line
    if t == "exit\r\n" { ExitProcess("0") }
    if t == "exit\n"   { ExitProcess("0") }
    if t == "exit"     { ExitProcess("0") }
    emit ""
}

func onCmd() {
    let line = guiGetText(g_cmdline)
    if len(line) == 0 { emit "1" }
    let full = line + "\r\n"
    tryBuiltin(line)
    ptyWrite(full)
    guiSetText(g_cmdline, "")
}

// ── theme ────────────────────────────────────────────────────────────

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
    if v == "1" { emit "1" }
    emit "0"
}

// ── entry ─────────────────────────────────────────────────────────────

just run {
    let bg = "0x2d2d2d"
    if osIsLightMode() == "0" { bg = "0x0a0a0a" }
    let fg = "0xe8e8e8"
    guiSetWindowBg(bg)

    guiInit()
    g_win = guiWindow("stem", 1000, 640)

    g_output  = guiRichEdit(g_win,  0,   0, 1000, 600)
    g_cmdline = guiTextInput(g_win, 0, 600, 1000,  40)
    guiRichSetMonoFont(g_output, "Cascadia Mono", 11)
    guiRichSetBg(g_output, bg)
    guiRichSetFgDefault(g_output, fg)
    guiRichReadOnly(g_output, 1)
    guiOnClick(g_cmdline, funcptr(onCmd))

    g_readBuf = bufNew(4096)
    g_avail   = bufNew(4)
    g_read    = bufNew(4)

    appendOutput("stem v0.2 — pure-Krypton terminal (ConPTY).\n")
    if ptySpawn("cmd.exe", 100, 40) != "1" {
        appendOutput("ERROR: failed to spawn cmd.exe via ConPTY.\n")
    } else {
        guiSetTimer("30", funcptr(ptyDrainOnce))
    }

    guiShow(g_win)
    guiRun()
}
