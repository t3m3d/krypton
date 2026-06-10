// stem_win.ks — Windows port of stem (the terminal that pairs with brain).
//
// v0.1 matches what m shipped as "stem v0.1" inside brain.ks: a
// command-runner with output pane. Type a command, Enter, see output.
// Interactive ConPTY (long-running shell + live keystroke forwarding)
// is the v0.2 lift — ConPTY itself is already exposed in head:windows
// (CreatePseudoConsole / ResizePseudoConsole / ClosePseudoConsole, see
// headers/windows.krh:269).
//
// Build (from krypton/):
//   kcc.exe examples/objk/stem_win.ks -o stem.exe
//   .\stem.exe
//
// Pair / lineage:
//   examples/objk/brain_win.ks — has stem-v0.1 embedded as its console pane
//   examples/objk/brain.ks     — macOS sibling, same stem-v0.1 inside
//   This file                  — stem as a standalone window
//
// Why "objk" (Objective-K) on Windows: same KryptScript + GUI-binding
// pattern m uses on macOS. On Windows the binding stdlib is k:gui
// (Win32) instead of k:cocoa (Cocoa). No new runtime, no extra DLLs —
// just KryptScript + the existing gui.k.

import "k:gui"

let g_win       = 0
let g_output    = 0     // RichEdit, read-only, full transcript
let g_cmdline   = 0     // text input — type cmd, Enter to run
let g_cwd       = ""    // tracked working directory; changes follow `cd`

// ── OS theme detection (HKCU AppsUseLightTheme) ───────────────────────
// Returns "1" when Windows is in light mode, "0" when dark mode.
// stem inverts its bg from the OS: dark OS → gloss black, light OS →
// dark grey. So in either OS theme stem is the punchier dark surface.
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
    if v == "" { emit "1" }   // default to light if the key is missing
    if v == "1" { emit "1" }
    emit "0"
}

// ── ui helpers ────────────────────────────────────────────────────────

// Strip ANSI escape sequences from text before display. exec()'d shells
// often emit VT codes (colors, cursor moves) that RichEdit would render
// as literal "←[31m" garbage. v0.2 will parse + apply these via
// guiRichSetFmt; for v0.1 we just hide them. Drops everything between
// ESC (0x1b) and the next letter or '~' (handles CSI + most OSC).
func stripAnsi(s) {
    let n = len(s)
    let out = ""
    let i = 0
    while i < n {
        let c = s[i]
        if c != fromCharCode(27) {
            out = out + c
            i = i + 1
        } else {
            // Skip ESC, then skip until the terminating byte. CSI ends
            // on a letter (A-Z / a-z); OSC ends on BEL (0x07) or ST.
            i = i + 1
            // optional "[" or "]" intermediate byte
            if i < n { if s[i] == "[" { i = i + 1 }  }
            while i < n {
                let cc = s[i]
                let code = charCode(cc)
                if cc == fromCharCode(7) { i = i + 1  break }
                if code >= 64 { if code <= 126 { i = i + 1  break } }
                i = i + 1
            }
        }
    }
    emit out
}

func appendOutput(s) {
    let cur = guiGetText(g_output)
    guiSetText(g_output, cur + stripAnsi(s))
    emit "1"
}

// Update the title bar with the active cwd so users see where they are.
func refreshTitle() {
    guiSetText(g_win, "stem — " + g_cwd)
    emit "1"
}

// ── command runner ────────────────────────────────────────────────────

// Returns the text following an initial "cd " (with surrounding spaces
// stripped), or "" when the line isn't a cd. We intercept cd here
// because exec() spawns a fresh cmd per call — directory changes inside
// that cmd are gone the moment it exits. We instead keep g_cwd in
// module state and prepend "cd <g_cwd> &&" to every run.
func parseCd(line) {
    let n = len(line)  let i = 0
    while i < n { if line[i] != " " { i = n + 1 }  i = i + 1 }
    let start = i - 1
    if start < 0 { emit "" }
    if start + 3 > n { emit "" }
    if substring(line, start, start + 3) != "cd " { emit "" }
    let arg = substring(line, start + 3, n)
    // trim trailing spaces
    let e = len(arg)
    while e > 0 {
        let lc = e - 1
        if arg[lc] != " " { emit substring(arg, 0, e) }
        e = e - 1
    }
    emit ""
}

// Normalise a cd target. Absolute paths replace cwd; bare names join.
// ".." pops one segment. No drive-letter handling beyond verbatim use.
func resolveCd(target) {
    if len(target) == 0 { emit g_cwd }
    // absolute on Windows: starts with drive letter or "\"
    if len(target) >= 2 { if target[1] == ":" { emit target } }
    if target[0] == "\\" { emit target }
    if target[0] == "/"  { emit target }
    if target == ".."    {
        let n = len(g_cwd)  let i = n - 1
        while i >= 0 {
            if g_cwd[i] == "\\" { emit substring(g_cwd, 0, i) }
            if g_cwd[i] == "/"  { emit substring(g_cwd, 0, i) }
            i = i - 1
        }
        emit g_cwd
    }
    emit g_cwd + "\\" + target
}

func runCommand(line) {
    let cdTarget = parseCd(line)
    if len(cdTarget) > 0 {
        g_cwd = resolveCd(cdTarget)
        appendOutput("$ " + line + "\n")
        refreshTitle()
        emit "1"
    }
    let full = "cd /d " + g_cwd + " && " + line + " 2>&1"
    let out = exec(full)
    appendOutput("$ " + line + "\n" + out + "\n")
    emit "1"
}

// Trim leading + trailing ASCII whitespace.
func isWs(c) {
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
        if isWs(s[a]) == "1" { a = a + 1 }
        else {
            // found first non-ws at a; now find last non-ws walking from end
            let b = n
            while b > a {
                if isWs(s[b - 1]) == "1" { b = b - 1 }
                else { emit substring(s, a, b) }
            }
            emit ""
        }
    }
    emit ""
}

// Builtin commands handled in-process so they don't require spawning
// a subshell. Returns "1" if the line was a builtin (caller skips
// runCommand), "" otherwise.
func tryBuiltin(line) {
    let l = trimSpaces(line)
    if l == "clear" {
        guiSetText(g_output, "")
        guiSetText(g_cmdline, "")
        emit "1"
    }
    if l == "cls" {
        guiSetText(g_output, "")
        guiSetText(g_cmdline, "")
        emit "1"
    }
    if l == "exit" {
        // Hard exit — cleaner than tearing down the message loop
        // manually, and shells universally do this anyway.
        ExitProcess("0")
        emit "1"
    }
    emit ""
}

func onCmd() {
    let line = guiGetText(g_cmdline)
    if len(line) == 0 { emit "1" }
    if tryBuiltin(line) == "1" { emit "1" }
    runCommand(line)
    guiSetText(g_cmdline, "")
}

// ── app entry ─────────────────────────────────────────────────────────

just run {
    g_cwd = arg(0)
    if len(g_cwd) == 0 {
        // fall back to %USERPROFILE% so launching from Explorer feels natural
        g_cwd = exec("cmd /c echo %USERPROFILE%")
        // exec output trails with a newline; strip it
        let n = len(g_cwd)
        while n > 0 {
            let lc = n - 1
            if g_cwd[lc] != "\n" { if g_cwd[lc] != "\r" { g_cwd = substring(g_cwd, 0, n)  n = 0 - 1 } }
            n = n - 1
        }
    }

    // Theme: gloss black under dark OS, dark grey under light OS.
    // Either way the chrome reads as a deliberately darker surface than
    // its surroundings. Foreground stays a soft off-white for legibility.
    let bg = "2d2d2d"
    if osIsLightMode() == "0" { bg = "0a0a0a" }
    let fg = "e8e8e8"
    guiSetWindowBg(bg)

    guiInit()
    g_win = guiWindow("stem", 900, 600)

    g_output  = guiRichEdit(g_win,  0,   0, 900, 560)
    g_cmdline = guiTextInput(g_win, 0, 560, 900,  40)
    guiRichSetMonoFont(g_output, "Cascadia Mono", 11)
    guiRichSetBg(g_output, bg)
    guiRichSetFgDefault(g_output, fg)
    guiRichReadOnly(g_output, 1)

    // Enter on the text input fires guiOnClick in gui.k. Same shape as
    // brain.ks's cmdfield + onCmd handler.
    guiOnClick(g_cmdline, funcptr(onCmd))

    refreshTitle()
    appendOutput("stem v0.1.1 — pure-Krypton terminal (objk/Win32).\n")
    appendOutput("builtins: clear / cls / exit. cd persists across commands.\n")
    appendOutput("ANSI escape sequences in output are filtered (v0.2 will\n")
    appendOutput("render colour via guiRichSetFmt).\n\n")

    guiShow(g_win)
    guiRun()
}
