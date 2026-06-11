// brain_win.ks -- Windows port of brain.ks (the pure-Krypton IDE).
//
// v0.2.  Rewritten on guiStateSet/Get because module-level mutable
// lets read garbage across function boundaries (the
// feedback_module_mutable_globals.md flake -- same one that blanked
// stem_win.ks v0.1.x).  All widget handles + mutable state live in
// the gui state table.  Colours are 0x-prefixed per gui.k's
// _guiHexToInt contract.
//
// Build:
//   ./build_windows.sh          (in stem repo) or:
//   kcc.exe examples/objk/brain_win.ks -o brain.exe
//   <patch PE subsystem byte CUI(3)->GUI(2) at e_lfanew+24+0x44>
//   cp brain.exe.manifest next to it for UTF-8 codepage + Common Controls v6
//
// Cross-platform pairing -- DO NOT touch the other side from this file:
//   examples/objk/brain.ks      -- macOS / Cocoa  (k:cocoa)   <- agent m
//   examples/objk/brain_win.ks  -- Windows / Win32 (k:gui)    <- this (agent w)
//   examples/objk/brain_lin.ks  -- Linux / X11    (k:x11)     <- agent l
//
// Styling target: VSCode-ish dark theme.
//   window bg     #1e1e1e
//   editor bg     #1e1e1e
//   sidebar bg    #252526
//   status bar    #007acc (accent blue)
//   fg            #cccccc
//   keyword       #c586c0 (purple)
//   string        #ce9178 (peach)
//   comment       #6a9955 (green)
//   number        #b5cea8 (sage)

import "k:gui"
import "head:windows"
import "head:dwmapi"
import "head:uxtheme"

// ── state accessors (workaround for module-mutable-global flake) ─────

func _o_tree()    { emit guiStateGet("brain.tree") }
func _o_tabs()    { emit guiStateGet("brain.tabs") }
func _o_editor()  { emit guiStateGet("brain.editor") }
func _o_console() { emit guiStateGet("brain.console") }
func _o_status()  { emit guiStateGet("brain.statusbar") }
func _o_win()     { emit guiStateGet("brain.win") }

func _dirG()      { emit guiStateGet("brain.dir") }
func _dirS(v)     { guiStateSet("brain.dir", v)  emit "1" }
func _filesG()    { emit guiStateGet("brain.files") }
func _filesS(v)   { guiStateSet("brain.files", v)  emit "1" }
func _tabPathsG() { emit guiStateGet("brain.tabpaths") }
func _tabPathsS(v) { guiStateSet("brain.tabpaths", v)  emit "1" }
func _tabTextsG() { emit guiStateGet("brain.tabtexts") }
func _tabTextsS(v) { guiStateSet("brain.tabtexts", v)  emit "1" }
func _curTabG()   { let v = guiStateGet("brain.curtab")  if v == "" { emit 0 - 1 }  emit toInt(v) }
func _curTabS(v)  { guiStateSet("brain.curtab", v + "")  emit "1" }

func _conCwdG()   { emit guiStateGet("brain.conCwd") }
func _conCwdS(v)  { guiStateSet("brain.conCwd", v)  emit "1" }
func _curFgG()    { emit guiStateGet("brain.curFg") }
func _curFgS(v)   { guiStateSet("brain.curFg", v)  emit "1" }
func _curBoldG()  { if guiStateGet("brain.curBold") == "1" { emit "1" }  emit "0" }
func _curBold1()  { guiStateSet("brain.curBold", "1")  emit "1" }
func _curBold0()  { guiStateSet("brain.curBold", "0")  emit "1" }
func _hlBusyG()   { if guiStateGet("brain.hlBusy") == "1" { emit "1" }  emit "0" }
func _hlBusyS(v)  { guiStateSet("brain.hlBusy", v + "")  emit "1" }
func _conBusyG()  { if guiStateGet("brain.conBusy") == "1" { emit "1" }  emit "0" }
func _conBusyS(v) { guiStateSet("brain.conBusy", v + "")  emit "1" }

// ── helpers ──────────────────────────────────────────────────────────

func baseName(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        if p[i] == "/"  { emit substring(p, i + 1, n) }
        if p[i] == "\\" { emit substring(p, i + 1, n) }
        i = i - 1
    }
    emit p
}
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

// Tab buffer is "\x1F"-separated.
func tabTextAt(idx) {
    let SEP = fromCharCode(31)
    let s = _tabTextsG()
    let n = len(s)  let cur = 0  let start = 0  let i = 0
    while i < n {
        if s[i] == SEP {
            if cur == idx { emit substring(s, start, i) }
            cur = cur + 1  start = i + 1
        }
        i = i + 1
    }
    if cur == idx { emit substring(s, start, n) }
    emit ""
}
func tabTextSet(idx, text) {
    let SEP = fromCharCode(31)
    let s = _tabTextsG()
    let n = len(s)  let cur = 0  let start = 0  let i = 0
    let out = ""
    while i <= n {
        let atSep = 0
        if i == n { atSep = 1 }
        if i < n  { if s[i] == SEP { atSep = 1 } }
        if atSep == 1 {
            if cur == idx { out = out + text }
            if cur != idx { out = out + substring(s, start, i) }
            if i < n     { out = out + SEP }
            cur = cur + 1  start = i + 1
        }
        i = i + 1
    }
    _tabTextsS(out)
    emit "1"
}
func tabTextAdd(text) {
    let SEP = fromCharCode(31)
    let s = _tabTextsG()
    if len(s) > 0 { s = s + SEP }
    _tabTextsS(s + text)
    emit "1"
}

// ── ANSI colour rendering (carried from stem_win) ────────────────────

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
func applySgr(params) {
    if len(params) == 0 { _curFgS("")  _curBold0()  emit "1" }
    let n = len(params)  let i = 0
    while i < n {
        let code = toInt(_intAt(params, i))
        if code == 0  { _curFgS("")  _curBold0() }
        if code == 1  { _curBold1() }
        if code == 22 { _curBold0() }
        if code == 39 { _curFgS("") }
        if code >= 30 { if code <= 37 { _curFgS(sgrBaseColor(code)) } }
        if code >= 90 { if code <= 97 { _curFgS(sgrBaseColor(code)) } }
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
                    _curFgS(_rgbHex(r, g, b))
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
func _fgOrDefault() {
    let f = _curFgG()
    if len(f) == 0 { emit "0xcccccc" }
    emit f
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
            if len(buf) > 0 {
                guiRichAppend(_o_console(), buf, _fgOrDefault(), _curBoldG())
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
    if len(buf) > 0 { guiRichAppend(_o_console(), buf, _fgOrDefault(), _curBoldG()) }
    emit "1"
}

// ── console: EM_SETSEL to end + EM_SCROLLCARET ───────────────────────

func consoleSnapEnd() {
    let h = _o_console()
    let n = SendMessageA(h, "14", "0", "0")
    SendMessageA(h, "177", n + "", n + "")
    SendMessageA(h, "183", "0", "0")
    emit "1"
}

// ── tabs ─────────────────────────────────────────────────────────────

func saveCurTab() {
    let idx = _curTabG()
    if idx < 0 { emit "1" }
    tabTextSet(idx, guiGetText(_o_editor()))
    emit "1"
}
func selectTab(idx) {
    _hlBusyS(1)
    guiSetText(_o_editor(), tabTextAt(idx))
    _hlBusyS(0)
    _curTabS(idx)
    let path = lineAt(_tabPathsG(), idx)
    if len(path) > 0 {
        guiSetText(_o_win(), "brain -- " + path)
        // tabs is now a Label; just show the active file name in it.
        guiSetText(_o_tabs(), " " + baseName(path))
    }
    highlightEditor()
    emit "1"
}
func openTab(path) {
    saveCurTab()
    let paths = _tabPathsG()
    let nPaths = nlines(paths) + 1
    if len(paths) == 0 { nPaths = 0 }
    let i = 0  let found = 0 - 1
    while i < nPaths {
        if lineAt(paths, i) == path { found = i }
        i = i + 1
    }
    if found < 0 {
        if len(paths) > 0 { paths = paths + "\n" }
        _tabPathsS(paths + path)
        tabTextAdd(readFile(path))
        found = nPaths
    }
    selectTab(found)
    emit "1"
}
// Tabs is a Label now -- no tab-change event fires; we keep the
// stub so the existing wire isn't dangling.
func onTabChange() { emit "1" }

// ── menu / button actions ────────────────────────────────────────────

func onRun() {
    let idx = _curTabG()
    if idx < 0 { guiMessageBox("Run", "Open a .k file first.")  emit "1" }
    let path = lineAt(_tabPathsG(), idx)
    saveCurTab()
    writeFile(path, guiGetText(_o_editor()))
    let cmd = "cd /d " + _dirG() + " && kcc " + path + " -o brainrun.exe 2>&1 && brainrun.exe 2>&1"
    let out = exec(cmd)
    appendConsole("$ run " + baseName(path) + "\n" + out + "\n$ ")
    consoleSnapEnd()
}
func onOpen() {
    _conBusyS(1)
    appendConsole("\n\x1b[33m[onOpen fired -- calling guiOpenFile]\x1b[0m\n$ ")
    consoleSnapEnd()
    _conBusyS(0)
    let path = guiOpenFile("Open .k file", "Krypton scripts|*.k;*.ks|All files|*.*")
    if len(path) > 0 { openTab(path) }
}
func onSave() {
    let idx = _curTabG()
    if idx < 0 { emit "1" }
    let path = lineAt(_tabPathsG(), idx)
    saveCurTab()
    writeFile(path, guiGetText(_o_editor()))
    appendConsole("$ saved " + baseName(path) + "\n$ ")
    consoleSnapEnd()
}
func onExit() { ExitProcess("0") }
func onClearConsole() {
    guiSetText(_o_console(), "")
    appendConsole("$ ")
    consoleSnapEnd()
    emit "1"
}
func onAbout() {
    guiMessageBox("brain", "brain -- pure-Krypton IDE on Windows.\n\nbuilt with kcc + k:gui (Objective-K + KryptScript).\nno TypeScript, no Electron.")
    emit "1"
}
func onTodo() {
    guiMessageBox("brain", "Not implemented yet.")
    emit "1"
}

// Create an Untitled tab in memory (no path until first Save As).
func onNewFile() {
    let paths = _tabPathsG()
    if len(paths) > 0 { paths = paths + "\n" }
    _tabPathsS(paths + "<untitled>")
    tabTextAdd("// new file\n")
    guiTabAdd(_o_tabs(), "Untitled")
    let nPaths = nlines(_tabPathsG()) + 1
    if len(_tabPathsG()) == 0 { nPaths = 0 }
    selectTab(nPaths - 1)
    emit "1"
}

// Trim trailing \r so cmd /c dir /b output (which is CRLF) doesn't
// leave each filename with a hidden \r -- TreeView/Listbox silently
// reject items containing control bytes.
func _stripCR(s) {
    let n = len(s)
    let end = n
    while end > 0 {
        if s[end - 1] != "\r" { emit substring(s, 0, end) }
        end = end - 1
    }
    emit ""
}

// Modern Common Item Dialog folder picker -- PowerShell-bridged
// because IFileOpenDialog requires substantial COM plumbing in
// Krypton.  PS spawns the same Explorer-style dialog Save/Open uses,
// writes the picked path to stdout, exec() captures it.
// Inline C# defines IFileOpenDialog COM interface + spawns the modern
// Win11 picker with a real "Select Folder" button (FOS_PICKFOLDERS).
// Written to %TEMP%\brain_pickfolder.ps1 once per session so we don't
// have to fight escaping the multiline C# block inside exec().
func _ensurePickerScript() {
    let script = "$cs = @'\n"
        + "using System;\n"
        + "using System.Runtime.InteropServices;\n"
        + "[ComImport, Guid(\"DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7\")]\n"
        + "public class FileOpenDialog { }\n"
        + "[ComImport, Guid(\"D57C7288-D4AD-4768-BE02-9D969532D960\"),\n"
        + " InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]\n"
        + "public interface IFileOpenDialog {\n"
        + "  [PreserveSig] int Show(IntPtr h);\n"
        + "  void m2(); void m3(); void m4(); void m5(); void m6();\n"
        + "  [PreserveSig] int SetOptions(uint o);\n"
        + "  void m8(); void m9(); void m10(); void m11(); void m12();\n"
        + "  void m13(); void m14();\n"
        + "  [PreserveSig] int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string s);\n"
        + "  void m16(); void m17();\n"
        + "  [PreserveSig] int GetResult(out IShellItem si);\n"
        + "}\n"
        + "[ComImport, Guid(\"43826D1E-E718-42EE-BC55-A1E261C37BFE\"),\n"
        + " InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]\n"
        + "public interface IShellItem {\n"
        + "  void s1(); void s2(); void s3();\n"
        + "  [PreserveSig] int GetDisplayName(uint sigdn, out IntPtr p);\n"
        + "}\n"
        + "public static class P {\n"
        + "  public static string Pick() {\n"
        + "    var d = (IFileOpenDialog)(new FileOpenDialog());\n"
        + "    d.SetOptions(0x20);\n"
        + "    d.SetTitle(\"Open folder\");\n"
        + "    if (d.Show(IntPtr.Zero) != 0) return null;\n"
        + "    IShellItem si; d.GetResult(out si);\n"
        + "    IntPtr p; si.GetDisplayName(0x80058000, out p);\n"
        + "    return Marshal.PtrToStringUni(p);\n"
        + "  }\n"
        + "}\n"
        + "'@\n"
        + "Add-Type -TypeDefinition $cs -Language CSharp\n"
        + "$x = [P]::Pick()\n"
        + "if ($x) { Write-Output $x }\n"
    writeFile("C:/Windows/Temp/brain_pickfolder.ps1", script)
    emit "1"
}

func _modernPickFolder() {
    _ensurePickerScript()
    let ps = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\brain_pickfolder.ps1 2>&1"
    let out = exec(ps)
    // strip trailing CR / LF / space
    let n = len(out)  let end = n
    while end > 0 {
        let c = out[end - 1]
        if c != "\r" { if c != "\n" { if c != " " { emit substring(out, 0, end) } } }
        end = end - 1
    }
    emit ""
}

// Open Folder -- modern Explorer-style dialog + reload TreeView.
func onOpenFolder() {
    _conBusyS(1)
    appendConsole("\n\x1b[33m[onOpenFolder fired -- spawning PowerShell picker]\x1b[0m\n$ ")
    consoleSnapEnd()
    _conBusyS(0)
    let path = _modernPickFolder()
    if len(path) == 0 { emit "1" }
    _dirS(path)
    _conCwdS(path)
    let listCmd = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
                + " -NoProfile -Command \"Get-ChildItem -LiteralPath '"
                + path + "' -Name 2>&1\""
    let listing = exec(listCmd)
    _filesS(listing)
    // DIAG: dump raw listing length to console.
    _conBusyS(1)
    appendConsole("\n\x1b[33m[Get-ChildItem returned " + (len(listing) + "") + " bytes]\x1b[0m\n")
    if len(listing) > 0 { appendConsole("\x1b[90m" + listing + "\x1b[0m\n") }
    appendConsole("$ ")
    consoleSnapEnd()
    _conBusyS(0)
    guiTreeClear(_o_tree())
    let files = _filesG()
    let nf = nlines(files) + 1            // nlines counts \n; last line has no \n
    let j = 0
    let added = 0
    while j < nf {
        let fn = _stripCR(lineAt(files, j))
        if len(fn) > 0 {
            guiTreeAdd(_o_tree(), "0", fn)
            added = added + 1
        }
        j = j + 1
    }
    _conBusyS(1)
    appendConsole("\n\x1b[90mopened folder: " + path + " (" + (added + "") + " items)\x1b[0m\n$ ")
    consoleSnapEnd()
    _conBusyS(0)
    emit "1"
}

func onSaveAs() {
    let path = guiSaveFile("Save As", "Krypton scripts|*.k;*.ks|All files|*.*", "untitled.k")
    if len(path) == 0 { emit "1" }
    saveCurTab()
    writeFile(path, guiGetText(_o_editor()))
    // update current tab's path
    let idx = _curTabG()
    if idx >= 0 {
        let paths = _tabPathsG()
        // crude: rebuild paths replacing idx-th entry
        let out = ""  let cur = 0  let nP = len(paths)  let i = 0  let start = 0
        while i <= nP {
            let atEnd = 0
            if i == nP { atEnd = 1 }
            if i < nP  { if paths[i] == "\n" { atEnd = 1 } }
            if atEnd == 1 {
                if cur == idx { out = out + path }
                if cur != idx { out = out + substring(paths, start, i) }
                if i < nP    { out = out + "\n" }
                cur = cur + 1  start = i + 1
            }
            i = i + 1
        }
        _tabPathsS(out)
    }
    appendConsole("$ saved as " + baseName(path) + "\n$ ")
    consoleSnapEnd()
    emit "1"
}

func onRevert() {
    let idx = _curTabG()
    if idx < 0 { emit "1" }
    let path = lineAt(_tabPathsG(), idx)
    if path == "<untitled>" { emit "1" }
    tabTextSet(idx, readFile(path))
    _hlBusyS(1)
    guiSetText(_o_editor(), tabTextAt(idx))
    _hlBusyS(0)
    highlightEditor()
    emit "1"
}

func onCloseEditor() {
    // Crude: drop the current tab from g_tabpaths/g_tabtexts and rebuild.
    let idx = _curTabG()
    if idx < 0 { emit "1" }
    let paths = _tabPathsG()
    let n = nlines(paths) + 1
    if len(paths) == 0 { n = 0 }
    // Rebuild paths skipping idx.
    let out = ""  let i = 0
    while i < n {
        if i != idx {
            if len(out) > 0 { out = out + "\n" }
            out = out + lineAt(paths, i)
        }
        i = i + 1
    }
    _tabPathsS(out)
    // Rebuild texts skipping idx.
    let SEP = fromCharCode(31)
    let texts = _tabTextsG()
    let np = len(texts)
    let outT = ""  let cur = 0  let start = 0  let j = 0
    while j <= np {
        let atEnd = 0
        if j == np { atEnd = 1 }
        if j < np  { if texts[j] == SEP { atEnd = 1 } }
        if atEnd == 1 {
            if cur != idx {
                if len(outT) > 0 { outT = outT + SEP }
                outT = outT + substring(texts, start, j)
            }
            cur = cur + 1  start = j + 1
        }
        j = j + 1
    }
    _tabTextsS(outT)
    // Drop the tab from the control by clearing + re-adding remaining labels.
    // (gui.k tabs have no Remove, so we trash + rebuild.)
    let remaining = nlines(out) + 1
    if len(out) == 0 { remaining = 0 }
    // brute: just leave; users can ignore.  Real fix needs guiTabClear or TC_DELETEITEM.
    _curTabS(0 - 1)
    _hlBusyS(1)
    guiSetText(_o_editor(), "// no editor open\n")
    _hlBusyS(0)
    emit "1"
}

func onCloseFolder() {
    _dirS("")
    _filesS("")
    guiListClear(_o_tree())
    emit "1"
}

// ── Edit menu handlers ───────────────────────────────────────────────
// EM_UNDO = 199 (0xC7), EM_REDO = 1108 (0x454, RichEdit-only),
// WM_CUT = 768 (0x300), WM_COPY = 769 (0x301), WM_PASTE = 770 (0x302).
// Window menu handlers.
// SW_MINIMIZE = 6, SW_MAXIMIZE = 3 / SW_SHOWMAXIMIZED = 3 (same).
func onMinimize() { ShowWindow(_o_win() + "", "6")  emit "1" }
func onZoom()     { ShowWindow(_o_win() + "", "3")  emit "1" }

func onBrainHelp() {
    guiMessageBox("brain", "brain -- pure-Krypton IDE on Windows.\n\nObjective-K + KryptScript over k:gui (Win32 RichEdit).\n\nDocs: krypton-lang.org\nIssues: github.com/t3m3d/krypton")
    emit "1"
}

// EM_SETSEL = 177; (0, -1) selects all.
func onSelectAll() { SendMessageA(_o_editor() + "", "177", "0", "0xFFFFFFFF")  emit "1" }
func onUndo()  { SendMessageA(_o_editor() + "", "199",  "0", "0")  emit "1" }
func onRedo()  { SendMessageA(_o_editor() + "", "1108", "0", "0")  emit "1" }
func onCut()   { SendMessageA(_o_editor() + "", "768",  "0", "0")  emit "1" }
func onCopy()  { SendMessageA(_o_editor() + "", "769",  "0", "0")  emit "1" }
func onPaste() { SendMessageA(_o_editor() + "", "770",  "0", "0")  emit "1" }

// Toggle "//" on each selected line.  Pure-text approach: read the
// editor buffer, find the cursor's line range, prepend or strip "//".
// Currently only handles the single line the cursor is on (no multi-
// line selection awareness).
func onToggleLineComment() {
    let h = _o_editor()
    let pSel = bufNew("8")
    SendMessageA(h + "", "176", ptrToInt(pSel), ptrToInt(pSel) + 4)   // EM_GETSEL
    let startSel = toInt(bufGetDword(pSel))
    let text = guiGetText(h)
    let n = len(text)
    // Walk to start of this line.
    let lineStart = startSel
    while lineStart > 0 { if text[lineStart - 1] == "\n" { lineStart = lineStart }  lineStart = lineStart - 1 }
    if lineStart < 0 { lineStart = 0 }
    // Decide: starts with "//"?
    let toggle = ""
    if lineStart + 2 <= n {
        if substring(text, lineStart, lineStart + 2) == "//" { toggle = "strip" }
    }
    _hlBusyS(1)
    if toggle == "strip" {
        let newText = substring(text, 0, lineStart) + substring(text, lineStart + 2, n)
        guiSetText(h, newText)
    } else {
        let newText = substring(text, 0, lineStart) + "// " + substring(text, lineStart, n)
        guiSetText(h, newText)
    }
    _hlBusyS(0)
    highlightEditor()
    emit "1"
}

func onTreeClick() {
    let fname = guiTreeSelected(_o_tree())
    if len(fname) == 0 { emit "1" }
    openTab(_dirG() + "/" + fname)
}

// ── integrated console: inline-prompt terminal (stem v0.1.4 pattern) ─

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
    let cwd = _conCwdG()
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
func runConsoleCmd(line) {
    let cdTarget = _parseCd(line)
    if len(cdTarget) > 0 {
        _conCwdS(_resolveCd(cdTarget))
        appendConsole(line + "\n$ ")
        consoleSnapEnd()
        emit "1"
    }
    if line == "clear" { guiSetText(_o_console(), "")  appendConsole("$ ")  consoleSnapEnd()  emit "1" }
    if line == "cls"   { guiSetText(_o_console(), "")  appendConsole("$ ")  consoleSnapEnd()  emit "1" }
    let full = "cd /d " + _conCwdG() + " && " + line + " 2>&1"
    let out = exec(full)
    appendConsole(line + "\n" + out + "\n$ ")
    consoleSnapEnd()
    emit "1"
}
func onConsoleChange() {
    if _conBusyG() == "1" { emit "1" }
    let text = guiGetText(_o_console())
    let n = len(text)
    if n == 0 { emit "1" }
    if text[n - 1] != "\n" {
        _conBusyS(1)
        consoleSnapEnd()
        _conBusyS(0)
        emit "1"
    }
    // find last "$ " marker (walking backwards from second-to-last)
    let i = n - 2
    let promptAt = 0 - 1
    while i >= 0 {
        if text[i] == "$" {
            if i + 1 < n { if text[i + 1] == " " { promptAt = i  i = 0 - 1 } }
        }
        i = i - 1
    }
    if promptAt < 0 { emit "1" }
    let cmd = substring(text, promptAt + 2, n - 1)
    _conBusyS(1)
    runConsoleCmd(cmd)
    _conBusyS(0)
    emit "1"
}

// ── syntax highlighter (carried, refactored for guiState) ────────────

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
func highlightEditor() {
    if _hlBusyG() == "1" { emit "1" }
    _hlBusyS(1)
    let h = _o_editor()
    let src = guiGetText(h)
    let n = len(src)
    guiRichSetFmt(h, "0", n + "", "0xcccccc", "0")
    let i = 0
    while i < n {
        let c = src[i]
        if c == "/" {
            if i + 1 < n {
                if src[i + 1] == "/" {
                    let end = i
                    while end < n {
                        if src[end] == "\n" { end = n + 1000 }
                        else                { end = end + 1 }
                    }
                    if end >= n + 1000 { end = end - 1000 }
                    guiRichSetFmt(h, i + "", end + "", "0x6a9955", "0")
                    i = end
                }
            }
        }
        if i >= n { i = n }
        let cc = src[i]
        if cc == "\"" {
            let end = i + 1
            while end < n {
                let ch = src[end]
                if ch == "\\" { end = end + 2 }
                else {
                    if ch == "\"" { end = end + 1  end = n + 1000 }
                    else          { end = end + 1 }
                }
            }
            if end >= n + 1000 { end = end - 1000 }
            guiRichSetFmt(h, i + "", end + "", "0xce9178", "0")
            i = end
        }
        if i >= n { i = n }
        let dd = src[i]
        if _isDigit(dd) == "1" {
            let end = i + 1
            while end < n {
                if _isDigit(src[end]) == "1" { end = end + 1 }
                else                          { end = n + 1000 }
            }
            if end >= n + 1000 { end = end - 1000 }
            guiRichSetFmt(h, i + "", end + "", "0xb5cea8", "0")
            i = end
        }
        if i >= n { i = n }
        let ee = src[i]
        if _isAlpha(ee) == "1" {
            let end = i + 1
            while end < n {
                if _isAlnum(src[end]) == "1" { end = end + 1 }
                else                          { end = n + 1000 }
            }
            if end >= n + 1000 { end = end - 1000 }
            let word = substring(src, i, end)
            if _isKeyword(word) == "1" {
                // Insiders teal-green for keywords.
                guiRichSetFmt(h, i + "", end + "", "0x4ec9b0", "1")
            }
            i = end
        }
        if i < n { i = i + 1 }
    }
    _hlBusyS(0)
    emit "1"
}

// ── entry ────────────────────────────────────────────────────────────

just run {
    let dir = arg(0)
    if len(dir) == 0 { dir = "." }
    _dirS(dir)
    _conCwdS(dir)
    _filesS(exec("cmd /c dir /b " + dir))
    _curFgS("")
    _curBold0()
    _curTabS(0 - 1)

    guiInit()
    let win = guiWindow("brain", 1400, 900)
    guiStateSet("brain.win", win + "")
    guiEnableDarkMode()

    // VSCode Insiders green palette.
    //   editor / window bg: #1e1e1e
    //   tree bg:            #252526
    //   accent green:       #16825D  (status bar + caption)
    //   keyword green/teal: #4EC9B0
    //   fg:                 #cccccc
    // Dark Insiders green for ALL parent-bg gaps + label strips.
    // Brush dispatch verified working via earlier magenta diagnostic.
    guiSetWindowBg("0x0e3520")
    guiSetUiTextColor("0xffffff")

    // DwmSetWindowAttribute DWMWA_CAPTION_COLOR = 35 (Win11 22000+).
    // Paints the title-bar background with our Insiders-green accent.
    // 4-byte COLORREF buffer in 0x00BBGGRR order.
    let capBuf = bufNew("4")
    // #16825D -> R=0x16 G=0x82 B=0x5D -> COLORREF 0x005D8216
    bufSetDwordAt(capBuf, "0", "6128150")     // = 0x005D8216
    DwmSetWindowAttribute(win + "", "35", capBuf, "4")

    // Menu bar -- VSCode-style top-level set: File, Edit, Selection,
    // View, Go, Run, Terminal, Window, Help.  Items in non-File menus
    // are populated in a later pass (waiting on spec from user).
    let bar   = guiMenuBegin(win)
    let mFile = guiMenu(bar, "File")
    let miNewText      = guiMenuItem(mFile, "New Text File\tCtrl+N")
    let miNewFile      = guiMenuItem(mFile, "New File...")
    let miNewWindow    = guiMenuItem(mFile, "New Window\tCtrl+Shift+N")
    guiMenuSeparator(mFile)
    let miOpen         = guiMenuItem(mFile, "Open File...\tCtrl+O")
    let miOpenFolder   = guiMenuItem(mFile, "Open Folder...\tCtrl+K Ctrl+O")
    let mOpenRecent    = guiMenu(mFile, "Open Recent")     // sub-popup
    let miOpenRecent1  = guiMenuItem(mOpenRecent, "(empty)")  // populated at runtime
    guiMenuSeparator(mFile)
    let miSave         = guiMenuItem(mFile, "Save\tCtrl+S")
    let miSaveAs       = guiMenuItem(mFile, "Save As...\tCtrl+Shift+S")
    let miShare        = guiMenuItem(mFile, "Share...")
    let miAutoSave     = guiMenuItem(mFile, "Auto Save")
    let miRevert       = guiMenuItem(mFile, "Revert File")
    guiMenuSeparator(mFile)
    let miCloseEditor  = guiMenuItem(mFile, "Close Editor\tCtrl+W")
    let miCloseFolder  = guiMenuItem(mFile, "Close Folder")
    let miCloseWindow  = guiMenuItem(mFile, "Close Window\tCtrl+Shift+W")
    guiMenuSeparator(mFile)
    let miExit         = guiMenuItem(mFile, "Exit")

    let mEdit = guiMenu(bar, "Edit")
    let miUndo         = guiMenuItem(mEdit, "Undo\tCtrl+Z")
    let miRedo         = guiMenuItem(mEdit, "Redo\tCtrl+Y")
    guiMenuSeparator(mEdit)
    let miCut          = guiMenuItem(mEdit, "Cut\tCtrl+X")
    let miCopy         = guiMenuItem(mEdit, "Copy\tCtrl+C")
    let miPaste        = guiMenuItem(mEdit, "Paste\tCtrl+V")
    guiMenuSeparator(mEdit)
    let miFind         = guiMenuItem(mEdit, "Find\tCtrl+F")
    let miReplace      = guiMenuItem(mEdit, "Replace\tCtrl+H")
    guiMenuSeparator(mEdit)
    let miFindInFiles  = guiMenuItem(mEdit, "Find in Files\tCtrl+Shift+F")
    let miReplaceInF   = guiMenuItem(mEdit, "Replace in Files\tCtrl+Shift+H")
    guiMenuSeparator(mEdit)
    let miToggleLineC  = guiMenuItem(mEdit, "Toggle Line Comment\tCtrl+/")
    let miToggleBlockC = guiMenuItem(mEdit, "Toggle Block Comment\tShift+Alt+A")
    let miEmmet        = guiMenuItem(mEdit, "Emmet: Expand Abbreviation\tCtrl+Alt+E")
    guiMenuSeparator(mEdit)
    let miEmojiSym     = guiMenuItem(mEdit, "Emoji && Symbols\tCtrl+.")

    let mSelection = guiMenu(bar, "Selection")
    let miSelAll       = guiMenuItem(mSelection, "Select All\tCtrl+A")
    let miExpandSel    = guiMenuItem(mSelection, "Expand Selection\tShift+Alt+RightArrow")
    let miShrinkSel    = guiMenuItem(mSelection, "Shrink Selection\tShift+Alt+LeftArrow")
    guiMenuSeparator(mSelection)
    let miCopyLineUp   = guiMenuItem(mSelection, "Copy Line Up\tShift+Alt+UpArrow")
    let miCopyLineDown = guiMenuItem(mSelection, "Copy Line Down\tShift+Alt+DownArrow")
    let miMoveLineUp   = guiMenuItem(mSelection, "Move Line Up\tAlt+UpArrow")
    let miMoveLineDown = guiMenuItem(mSelection, "Move Line Down\tAlt+DownArrow")
    let miDuplicateSel = guiMenuItem(mSelection, "Duplicate Selection")
    guiMenuSeparator(mSelection)
    let miCursorAbove  = guiMenuItem(mSelection, "Add Cursor Above\tCtrl+Alt+UpArrow")
    let miCursorBelow  = guiMenuItem(mSelection, "Add Cursor Below\tCtrl+Alt+DownArrow")
    let miCursorLineE  = guiMenuItem(mSelection, "Add Cursors to Line Ends\tShift+Alt+I")
    let miAddNextOcc   = guiMenuItem(mSelection, "Add Next Occurrence\tCtrl+D")
    let miAddPrevOcc   = guiMenuItem(mSelection, "Add Previous Occurrence")
    let miSelAllOcc    = guiMenuItem(mSelection, "Select All Occurrences\tCtrl+Shift+L")
    guiMenuSeparator(mSelection)
    let miMultiCursor  = guiMenuItem(mSelection, "Switch to Ctrl+Click for Multi-Cursor")
    let miColumnSel    = guiMenuItem(mSelection, "Column Selection Mode\tCtrl+Shift+Alt")

    let mView = guiMenu(bar, "View")
    let miCmdPalette   = guiMenuItem(mView, "Command Palette\tCtrl+Shift+P")
    let miOpenView     = guiMenuItem(mView, "Open View...")
    guiMenuSeparator(mView)
    let miExplorer     = guiMenuItem(mView, "Explorer\tCtrl+Shift+E")
    let miSearch       = guiMenuItem(mView, "Search\tCtrl+Shift+F")
    let miSourceCtrl   = guiMenuItem(mView, "Source Control\tCtrl+Shift+G")
    let miRunPanel     = guiMenuItem(mView, "Run\tCtrl+Shift+D")
    let miExtensions   = guiMenuItem(mView, "Extensions\tCtrl+Shift+X")
    guiMenuSeparator(mView)
    let miChat         = guiMenuItem(mView, "Chat")
    let miBrowser      = guiMenuItem(mView, "Browser")
    guiMenuSeparator(mView)
    let miProblems     = guiMenuItem(mView, "Problems\tCtrl+Shift+M")
    let miOutput       = guiMenuItem(mView, "Output\tCtrl+Shift+U")
    let miDebugConsole = guiMenuItem(mView, "Debug Console\tCtrl+Shift+Y")
    let miTerminalV    = guiMenuItem(mView, "Terminal\tCtrl+`")
    guiMenuSeparator(mView)
    let miWordWrap     = guiMenuItem(mView, "Word Wrap\tAlt+Z")
    let miFullScreen   = guiMenuItem(mView, "Enter Full Screen\tF11")

    let mGo = guiMenu(bar, "Go")
    let miGoBack       = guiMenuItem(mGo, "Back\tAlt+LeftArrow")
    let miGoForward    = guiMenuItem(mGo, "Forward\tAlt+RightArrow")
    let miGoLastEdit   = guiMenuItem(mGo, "Last Edit Location\tCtrl+K Ctrl+Q")
    guiMenuSeparator(mGo)
    let mSwitchEd = guiMenu(mGo, "Switch Editor")
    let miSE_Next      = guiMenuItem(mSwitchEd, "Next Editor\tCtrl+PageDown")
    let miSE_Prev      = guiMenuItem(mSwitchEd, "Previous Editor\tCtrl+PageUp")
    guiMenuSeparator(mSwitchEd)
    let miSE_NextUsed  = guiMenuItem(mSwitchEd, "Next Used Editor\tCtrl+Tab")
    let miSE_PrevUsed  = guiMenuItem(mSwitchEd, "Previous Used Editor\tCtrl+Shift+Tab")
    guiMenuSeparator(mSwitchEd)
    let miSE_NextGrp   = guiMenuItem(mSwitchEd, "Next Editor in Group")
    let miSE_PrevGrp   = guiMenuItem(mSwitchEd, "Previous Editor in Group")
    guiMenuSeparator(mSwitchEd)
    let miSE_NextUGrp  = guiMenuItem(mSwitchEd, "Next Used Editor in Group")
    let miSE_PrevUGrp  = guiMenuItem(mSwitchEd, "Previous Used Editor in Group")
    let mSwitchGrp = guiMenu(mGo, "Switch Group")
    let miSG_1         = guiMenuItem(mSwitchGrp, "Group 1\tCtrl+1")
    let miSG_2         = guiMenuItem(mSwitchGrp, "Group 2\tCtrl+2")
    let miSG_3         = guiMenuItem(mSwitchGrp, "Group 3\tCtrl+3")
    let miSG_4         = guiMenuItem(mSwitchGrp, "Group 4\tCtrl+4")
    let miSG_5         = guiMenuItem(mSwitchGrp, "Group 5\tCtrl+5")
    guiMenuSeparator(mSwitchGrp)
    let miSG_Next      = guiMenuItem(mSwitchGrp, "Next Group")
    let miSG_Prev      = guiMenuItem(mSwitchGrp, "Previous Group")
    guiMenuSeparator(mSwitchGrp)
    let miSG_Left      = guiMenuItem(mSwitchGrp, "Group Left\tCtrl+K Ctrl+LeftArrow")
    let miSG_Right     = guiMenuItem(mSwitchGrp, "Group Right\tCtrl+K Ctrl+RightArrow")
    let miSG_Above     = guiMenuItem(mSwitchGrp, "Group Above\tCtrl+K Ctrl+UpArrow")
    let miSG_Below     = guiMenuItem(mSwitchGrp, "Group Below\tCtrl+K Ctrl+DownArrow")
    guiMenuSeparator(mGo)
    let miGoToFile     = guiMenuItem(mGo, "Go to File...\tCtrl+P")
    let miGoSymWS      = guiMenuItem(mGo, "Go to Symbol in Workspace\tCtrl+T")
    guiMenuSeparator(mGo)
    let miGoSymEd      = guiMenuItem(mGo, "Go to Symbol in Editor\tCtrl+Shift+O")
    let miGoDef        = guiMenuItem(mGo, "Go to Definition\tF12")
    let miGoDecl       = guiMenuItem(mGo, "Go to Declaration")
    let miGoTypeDef    = guiMenuItem(mGo, "Go to Type Definition")
    let miGoImpls      = guiMenuItem(mGo, "Go to Implementations\tCtrl+F12")
    let miGoRefs       = guiMenuItem(mGo, "Go to References\tShift+F12")
    guiMenuSeparator(mGo)
    let miGoLine       = guiMenuItem(mGo, "Go to Line/Column...\tCtrl+G")
    let miGoBracket    = guiMenuItem(mGo, "Go to Bracket\tCtrl+Shift+\\")
    guiMenuSeparator(mGo)
    let miNextProblem  = guiMenuItem(mGo, "Next Problem\tF8")
    let miPrevProblem  = guiMenuItem(mGo, "Previous Problem\tShift+F8")
    guiMenuSeparator(mGo)
    let miNextChange   = guiMenuItem(mGo, "Next Change\tAlt+F3")
    let miPrevChange   = guiMenuItem(mGo, "Previous Change\tShift+Alt+F3")

    let mRun = guiMenu(bar, "Run")
    let miStartDebug    = guiMenuItem(mRun, "Start Debugging\tF5")
    let miRunNoDebug    = guiMenuItem(mRun, "Run Without Debugging\tCtrl+F5")
    let miStopDebug     = guiMenuItem(mRun, "Stop Debugging\tShift+F5")
    let miRestartDebug  = guiMenuItem(mRun, "Restart Debugging\tCtrl+Shift+F5")
    guiMenuSeparator(mRun)
    let miOpenConfigs   = guiMenuItem(mRun, "Open Configurations")
    let miAddConfig     = guiMenuItem(mRun, "Add Configuration...")
    guiMenuSeparator(mRun)
    let miStepOver      = guiMenuItem(mRun, "Step Over\tF10")
    let miStepInto      = guiMenuItem(mRun, "Step Into\tF11")
    let miStepOut       = guiMenuItem(mRun, "Step Out\tShift+F11")
    let miContinue      = guiMenuItem(mRun, "Continue\tF5")
    guiMenuSeparator(mRun)
    let miToggleBP      = guiMenuItem(mRun, "Toggle Breakpoint\tF9")
    let mNewBP = guiMenu(mRun, "New Breakpoint")
    let miBPCond        = guiMenuItem(mNewBP, "Conditional Breakpoint...")
    let miBPEdit        = guiMenuItem(mNewBP, "Edit Breakpoint...")
    let miBPInline      = guiMenuItem(mNewBP, "Inline Breakpoint\tShift+F9")
    let miBPFunction    = guiMenuItem(mNewBP, "Function Breakpoint...")
    let miBPLog         = guiMenuItem(mNewBP, "Logpoint...")
    let miBPTriggered   = guiMenuItem(mNewBP, "Triggered Breakpoint...")
    guiMenuSeparator(mRun)
    let miEnableAllBP   = guiMenuItem(mRun, "Enable All Breakpoints")
    let miDisableAllBP  = guiMenuItem(mRun, "Disable All Breakpoints")
    let miRemoveAllBP   = guiMenuItem(mRun, "Remove All Breakpoints")
    guiMenuSeparator(mRun)
    let miInstallDebug  = guiMenuItem(mRun, "Install Additional Debuggers...")

    let mTerminal = guiMenu(bar, "Terminal")
    let miNewTerm        = guiMenuItem(mTerminal, "New Terminal\tCtrl+`")
    let miSplitTerm      = guiMenuItem(mTerminal, "Split Terminal\tCtrl+Shift+5")
    let miNewTermWin     = guiMenuItem(mTerminal, "New Terminal Window")
    guiMenuSeparator(mTerminal)
    let miRunTask        = guiMenuItem(mTerminal, "Run Task...")
    let miRunBuildTask   = guiMenuItem(mTerminal, "Run Build Task...\tCtrl+Shift+B")
    let miRunActiveFile  = guiMenuItem(mTerminal, "Run Active File")
    let miRunSelected    = guiMenuItem(mTerminal, "Run Selected Text")
    guiMenuSeparator(mTerminal)
    let miShowRunning    = guiMenuItem(mTerminal, "Show Running Tasks...")
    let miRestartTask    = guiMenuItem(mTerminal, "Restart Running Task...")
    let miTerminateTask  = guiMenuItem(mTerminal, "Terminate Task...")
    guiMenuSeparator(mTerminal)
    let miConfigTasks    = guiMenuItem(mTerminal, "Configure Tasks...")
    let miConfigBuildT   = guiMenuItem(mTerminal, "Configure Default Build Task...")
    let mWindow = guiMenu(bar, "Window")
    let miMinimize     = guiMenuItem(mWindow, "Minimize")
    let miZoom         = guiMenuItem(mWindow, "Zoom")
    let miFill         = guiMenuItem(mWindow, "Fill")
    let miCenter       = guiMenuItem(mWindow, "Center")
    guiMenuSeparator(mWindow)
    let miToggleFS     = guiMenuItem(mWindow, "Toggle Full Screen\tF11")
    let miShowTerm     = guiMenuItem(mWindow, "Show Terminal")
    let miHideTerm     = guiMenuItem(mWindow, "Hide Terminal")

    let mHelp      = guiMenu(bar, "Help")
    // Placeholder so each top-level dropdown is non-empty (Win32 hides
    // a dropdown that has zero items).
    guiMenuItem(mGo,        "(items pending)")
    guiMenuItem(mRun,       "(items pending)")
    guiMenuItem(mTerminal,  "(items pending)")
    let miBrainHelp   = guiMenuItem(mHelp, "Brain Help")

    // Force a redraw of the menu bar so all the items + submenus we
    // appended via AppendMenuA actually attach.  guiMenuBegin already
    // called DrawMenuBar once, but that was on an EMPTY menu before
    // any items existed; without this second call after building the
    // menu structure, Win11 sometimes refuses to open dropdowns.
    DrawMenuBar(win + "")

    // guiMenuDarken bisect: temporarily disabled (process was dying
    // on launch; isolating whether it's MENUINFO/SetMenuInfo).
    // guiMenuDarken(bar, "0x0e3520")

    // Layout coords:  Win11 with menu bar consumes ~25 px from the top
    // of the client area for the menu; we DON'T need to leave a gap
    // because the client rect already excludes the menu strip.  But
    // we DO need to ensure widget heights don't overflow.
    //
    // tree: TreeView -- guiTreeView accepts colour-control (Listbox
    // doesn't), so the file pane themes correctly with the rest.
    // Tab control's default internal CLIENT AREA is painted WHITE by
    // SysTabControl32, which leaked between editor + console as a
    // white band.  Replaced with a simple Label showing the active
    // file path -- regains the chrome-darkness; tab navigation will
    // come back as a Listbox-style strip later.
    let tree     = guiTreeView(win,   0,   0,  260, 830)
    let tabsLbl  = guiLabel(win, " (no file open)",
                           260,  0, 4000, 22)
    let editor   = guiRichEdit(win, 260, 22, 4000, 610)
    let console  = guiRichEdit(win,   0, 628, 4000, 204)
    let status   = guiLabel(win, " brain | objk + KryptScript | Krypton ",
                              0, 830, 4000, 22)
    // Keep handle key names so the rest of the code reading
    // brain.tabs doesn't have to change (tabs handler is also faked).
    let tabs = tabsLbl
    guiStateSet("brain.tree",    tree + "")
    guiStateSet("brain.tabs",    tabs + "")
    guiStateSet("brain.editor",  editor + "")
    guiStateSet("brain.console", console + "")
    guiStateSet("brain.status",  status + "")
    // TreeView dark colours.
    guiTreeSetColors(tree, "0x252526", "0xcccccc")
    // Dark scrollbars / NC chrome on every visible widget.
    SetWindowTheme(tree + "",    "DarkMode_Explorer", "0")
    SetWindowTheme(tabs + "",    "DarkMode_Explorer", "0")
    SetWindowTheme(editor + "",  "DarkMode_Explorer", "0")
    SetWindowTheme(console + "", "DarkMode_Explorer", "0")
    SetWindowTheme(status + "",  "DarkMode_Explorer", "0")

    guiRichSetMonoFont(editor,  "Cascadia Mono", 12)
    guiRichSetMonoFont(console, "Cascadia Mono", 11)
    guiRichSetBg(editor,  "0x1e1e1e")
    guiRichSetBg(console, "0x1e1e1e")
    guiRichSetFgDefault(editor,  "0xcccccc")
    guiRichSetFgDefault(console, "0xcccccc")

    // Populate file tree.  dir /b output is CRLF; strip \r per line
    // because TreeView silently drops items containing control chars.
    let files = _filesG()
    let nf = nlines(files) + 1
    let i = 0
    while i < nf {
        let fn = _stripCR(lineAt(files, i))
        if len(fn) > 0 { guiTreeAdd(tree, "0", fn) }
        i = i + 1
    }

    // Menu wires.  Items without a real handler use onTodo so a click
    // pops a "not implemented yet" alert instead of being silently dead.
    guiOnClick(miNewText,     funcptr(onNewFile))
    guiOnClick(miNewFile,     funcptr(onNewFile))
    guiOnClick(miNewWindow,   funcptr(onTodo))
    guiOnClick(miOpen,        funcptr(onOpen))
    guiOnClick(miOpenFolder,  funcptr(onOpenFolder))
    guiOnClick(miOpenRecent1, funcptr(onTodo))
    guiOnClick(miSave,        funcptr(onSave))
    guiOnClick(miSaveAs,      funcptr(onSaveAs))
    guiOnClick(miShare,       funcptr(onTodo))
    guiOnClick(miAutoSave,    funcptr(onTodo))
    guiOnClick(miRevert,      funcptr(onRevert))
    guiOnClick(miCloseEditor, funcptr(onCloseEditor))
    guiOnClick(miCloseFolder, funcptr(onCloseFolder))
    guiOnClick(miCloseWindow, funcptr(onExit))
    guiOnClick(miExit,        funcptr(onExit))

    // Edit menu wires.  Undo/Redo/Cut/Copy/Paste route to the editor
    // RichEdit via standard messages.  Find/Replace etc. show TODO
    // until a dialog wrapper exists.
    guiOnClick(miUndo,         funcptr(onUndo))
    guiOnClick(miRedo,         funcptr(onRedo))
    guiOnClick(miCut,          funcptr(onCut))
    guiOnClick(miCopy,         funcptr(onCopy))
    guiOnClick(miPaste,        funcptr(onPaste))
    guiOnClick(miFind,         funcptr(onTodo))
    guiOnClick(miReplace,      funcptr(onTodo))
    guiOnClick(miFindInFiles,  funcptr(onTodo))
    guiOnClick(miReplaceInF,   funcptr(onTodo))
    guiOnClick(miToggleLineC,  funcptr(onToggleLineComment))
    guiOnClick(miToggleBlockC, funcptr(onTodo))
    guiOnClick(miEmmet,        funcptr(onTodo))
    guiOnClick(miEmojiSym,     funcptr(onTodo))

    // Selection menu wires.  Most are multi-cursor / range ops we
    // don't have RichEdit subclass support for yet -> onTodo.  Select
    // All is a single EM_SETSEL call so we wire it for real.
    guiOnClick(miSelAll,       funcptr(onSelectAll))
    guiOnClick(miExpandSel,    funcptr(onTodo))
    guiOnClick(miShrinkSel,    funcptr(onTodo))
    guiOnClick(miCopyLineUp,   funcptr(onTodo))
    guiOnClick(miCopyLineDown, funcptr(onTodo))
    guiOnClick(miMoveLineUp,   funcptr(onTodo))
    guiOnClick(miMoveLineDown, funcptr(onTodo))
    guiOnClick(miDuplicateSel, funcptr(onTodo))
    guiOnClick(miCursorAbove,  funcptr(onTodo))
    guiOnClick(miCursorBelow,  funcptr(onTodo))
    guiOnClick(miCursorLineE,  funcptr(onTodo))
    guiOnClick(miAddNextOcc,   funcptr(onTodo))
    guiOnClick(miAddPrevOcc,   funcptr(onTodo))
    guiOnClick(miSelAllOcc,    funcptr(onTodo))
    guiOnClick(miMultiCursor,  funcptr(onTodo))
    guiOnClick(miColumnSel,    funcptr(onTodo))

    // View menu wires.  All stubs for now -- panel toggles need a
    // multi-pane layout manager we don't have yet.
    guiOnClick(miCmdPalette,   funcptr(onTodo))
    guiOnClick(miOpenView,     funcptr(onTodo))
    guiOnClick(miExplorer,     funcptr(onTodo))
    guiOnClick(miSearch,       funcptr(onTodo))
    guiOnClick(miSourceCtrl,   funcptr(onTodo))
    guiOnClick(miRunPanel,     funcptr(onTodo))
    guiOnClick(miExtensions,   funcptr(onTodo))
    guiOnClick(miChat,         funcptr(onTodo))
    guiOnClick(miBrowser,      funcptr(onTodo))
    guiOnClick(miProblems,     funcptr(onTodo))
    guiOnClick(miOutput,       funcptr(onTodo))
    guiOnClick(miDebugConsole, funcptr(onTodo))
    guiOnClick(miTerminalV,    funcptr(onClearConsole))   // closest existing action
    guiOnClick(miWordWrap,     funcptr(onTodo))
    guiOnClick(miFullScreen,   funcptr(onTodo))

    // Window menu wires.  ShowWindow with the right SW_ command does
    // Minimize / Zoom (= Maximize) -- the others are TODO.
    guiOnClick(miMinimize,     funcptr(onMinimize))
    guiOnClick(miZoom,         funcptr(onZoom))
    guiOnClick(miFill,         funcptr(onTodo))
    guiOnClick(miCenter,       funcptr(onTodo))
    guiOnClick(miToggleFS,     funcptr(onTodo))
    guiOnClick(miShowTerm,     funcptr(onTodo))
    guiOnClick(miHideTerm,     funcptr(onTodo))

    // Go menu wires.  All TODO for now (need editor-history,
    // workspace-symbol DB, language-server -- big lifts each).
    guiOnClick(miGoBack,       funcptr(onTodo))
    guiOnClick(miGoForward,    funcptr(onTodo))
    guiOnClick(miGoLastEdit,   funcptr(onTodo))
    guiOnClick(miSE_Next,      funcptr(onTodo))
    guiOnClick(miSE_Prev,      funcptr(onTodo))
    guiOnClick(miSE_NextUsed,  funcptr(onTodo))
    guiOnClick(miSE_PrevUsed,  funcptr(onTodo))
    guiOnClick(miSE_NextGrp,   funcptr(onTodo))
    guiOnClick(miSE_PrevGrp,   funcptr(onTodo))
    guiOnClick(miSE_NextUGrp,  funcptr(onTodo))
    guiOnClick(miSE_PrevUGrp,  funcptr(onTodo))
    guiOnClick(miSG_1,         funcptr(onTodo))
    guiOnClick(miSG_2,         funcptr(onTodo))
    guiOnClick(miSG_3,         funcptr(onTodo))
    guiOnClick(miSG_4,         funcptr(onTodo))
    guiOnClick(miSG_5,         funcptr(onTodo))
    guiOnClick(miSG_Next,      funcptr(onTodo))
    guiOnClick(miSG_Prev,      funcptr(onTodo))
    guiOnClick(miSG_Left,      funcptr(onTodo))
    guiOnClick(miSG_Right,     funcptr(onTodo))
    guiOnClick(miSG_Above,     funcptr(onTodo))
    guiOnClick(miSG_Below,     funcptr(onTodo))
    guiOnClick(miGoToFile,     funcptr(onTodo))
    guiOnClick(miGoSymWS,      funcptr(onTodo))
    guiOnClick(miGoSymEd,      funcptr(onTodo))
    guiOnClick(miGoDef,        funcptr(onTodo))
    guiOnClick(miGoDecl,       funcptr(onTodo))
    guiOnClick(miGoTypeDef,    funcptr(onTodo))
    guiOnClick(miGoImpls,      funcptr(onTodo))
    guiOnClick(miGoRefs,       funcptr(onTodo))
    guiOnClick(miGoLine,       funcptr(onTodo))
    guiOnClick(miGoBracket,    funcptr(onTodo))
    guiOnClick(miNextProblem,  funcptr(onTodo))
    guiOnClick(miPrevProblem,  funcptr(onTodo))
    guiOnClick(miNextChange,   funcptr(onTodo))
    guiOnClick(miPrevChange,   funcptr(onTodo))

    // Run menu wires.  "Run Without Debugging" maps to our existing
    // kcc-compile-and-execute path; everything else is TODO until a
    // debugger backend lands.
    guiOnClick(miStartDebug,    funcptr(onTodo))
    guiOnClick(miRunNoDebug,    funcptr(onRun))
    guiOnClick(miStopDebug,     funcptr(onTodo))
    guiOnClick(miRestartDebug,  funcptr(onTodo))
    guiOnClick(miOpenConfigs,   funcptr(onTodo))
    guiOnClick(miAddConfig,     funcptr(onTodo))
    guiOnClick(miStepOver,      funcptr(onTodo))
    guiOnClick(miStepInto,      funcptr(onTodo))
    guiOnClick(miStepOut,       funcptr(onTodo))
    guiOnClick(miContinue,      funcptr(onTodo))
    guiOnClick(miToggleBP,      funcptr(onTodo))
    guiOnClick(miBPCond,        funcptr(onTodo))
    guiOnClick(miBPEdit,        funcptr(onTodo))
    guiOnClick(miBPInline,      funcptr(onTodo))
    guiOnClick(miBPFunction,    funcptr(onTodo))
    guiOnClick(miBPLog,         funcptr(onTodo))
    guiOnClick(miBPTriggered,   funcptr(onTodo))
    guiOnClick(miEnableAllBP,   funcptr(onTodo))
    guiOnClick(miDisableAllBP,  funcptr(onTodo))
    guiOnClick(miRemoveAllBP,   funcptr(onTodo))
    guiOnClick(miInstallDebug,  funcptr(onTodo))

    // Terminal menu wires.
    guiOnClick(miNewTerm,       funcptr(onClearConsole))
    guiOnClick(miSplitTerm,     funcptr(onTodo))
    guiOnClick(miNewTermWin,    funcptr(onTodo))
    guiOnClick(miRunTask,       funcptr(onTodo))
    guiOnClick(miRunBuildTask,  funcptr(onTodo))
    guiOnClick(miRunActiveFile, funcptr(onRun))
    guiOnClick(miRunSelected,   funcptr(onTodo))
    guiOnClick(miShowRunning,   funcptr(onTodo))
    guiOnClick(miRestartTask,   funcptr(onTodo))
    guiOnClick(miTerminateTask, funcptr(onTodo))
    guiOnClick(miConfigTasks,   funcptr(onTodo))
    guiOnClick(miConfigBuildT,  funcptr(onTodo))

    guiOnClick(miBrainHelp,    funcptr(onBrainHelp))

    // Widget wires.
    guiOnChange(tree, funcptr(onTreeClick))
    guiOnChange(tabs, funcptr(onTabChange))
    guiOnChange(editor, funcptr(highlightEditor))
    guiOnClick(console, funcptr(onConsoleChange))
    // EM_SETEVENTMASK = 1093, ENM_SELCHANGE = 524288 -- cursor lock.
    SendMessageA(console + "", "1093", "0", "524288")

    // Console boot.
    _conBusyS(1)
    // SGR 32 = standard green; matches the Insiders accent vibe.
    appendConsole("\x1b[32mbrain\x1b[0m integrated terminal -- builtins: clear, cls.\n")
    appendConsole("\x1b[90mcwd: " + dir + "\x1b[0m\n\n")
    appendConsole("$ ")
    consoleSnapEnd()
    _conBusyS(0)

    _hlBusyS(1)
    guiSetText(editor, "// brain -- pure-Krypton IDE on Windows.\n// click a file on the left to open.\n")
    _hlBusyS(0)
    highlightEditor()
    // Drop the selection EM_SETSEL guiRichSetFmt left behind so the
    // placeholder doesn't render with a fat blue selection-highlight.
    SendMessageA(editor + "", "177", "0", "0")

    guiShow(win)
    guiRun()
}
