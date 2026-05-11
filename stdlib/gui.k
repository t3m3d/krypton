// stdlib/gui.k — High-level cross-platform GUI library for Krypton.
//
// Wraps the boilerplate from examples/win_*.k into a small, opinionated
// API so a Krypton GUI program can stay short:
//
//   import "stdlib/gui.k"
//
//   func onHello() {
//       guiMessageBox("Hi", "Hello from Krypton!")
//   }
//
//   just run {
//       guiInit()
//       let win = guiWindow("Demo", 400, 220)
//       let edit = guiTextInput(win, 20, 20, 360, 26)
//       let btn  = guiButton(win, "Hello", 20, 60, 100, 30)
//       guiOnClick(btn, funcptr(onHello))
//       guiShow(win)
//       guiRun()
//   }
//
// Pure Krypton — every API below calls Win32 directly via IAT
// imports. The old cfunc {} body (compiled to ckrypton_gui.dll)
// was removed on 2026-05-11 after the WindowProc trampoline +
// state-store work made it fully unused. See project_phase_c_plan.md
// for the migration history.
//
// Backends:
//   Windows  — full surface (Win32 + Common Controls v6 + DWM).
//   macOS    — first slice via Cocoa over the Objective-C runtime
//              (NSWindow, NSButton, NSTextField, NSAlert). Widgets
//              not yet ported are no-op stubs so programs still link.
//   Linux    — no-op stubs; native GTK/X11 backend TBD.
//
// Build a GUI program:
//   Windows:  kcc my_gui.k -o my_gui.exe -luser32 -lgdi32 -lcomctl32 \
//                  -ldwmapi -luxtheme -ladvapi32
//   macOS:    kcc my_gui.k -o my_gui -Wl,-framework,Cocoa -lobjc

module gui

// Win32 API access for the pure-Krypton wrappers below.
import "head:user32"
import "head:dwmapi"
import "head:uxtheme"
import "head:comdlg32"




// ── Krypton public API ─────────────────────────────────────────

// 2026-05-11 Phase D: pure-Krypton WindowProc. Handles WM_CLOSE,
// WM_DESTROY, WM_COMMAND (button/menu clicks), WM_TIMER (Krypton-side
// timer dispatch). Callback registry uses guiState keys:
//   cb.click.<id>      — guiOnClick handler funcptr address (decimal)
//   cb.timer.<tid>     — guiSetTimer handler funcptr address (decimal)
// Falls through to DefWindowProcA for everything else.
func _krkWndProc(hwnd, msg, wParam, lParam) {
    let msgInt = toInt(msg)
    if msgInt == 16 {
        DestroyWindow(hwnd)
        emit "0"
    }
    if msgInt == 2 {
        PostQuitMessage("0")
        emit "0"
    }
    if msgInt == 273 {
        let id = bitAnd(wParam, "65535")
        let cb = guiStateGet("cb.click." + id)
        if cb != "" {
            callPtr(cb, "")
        }
        emit "0"
    }
    if msgInt == 275 {
        let cb = guiStateGet("cb.timer." + wParam)
        if cb != "" {
            callPtr(cb, "")
        }
        emit "0"
    }
    if msgInt == 78 {
        // WM_NOTIFY: wParam = idFrom (same as NMHDR.idFrom for convenience).
        // For subtype-specific code dispatch we'd need to deref lParam → NMHDR.code,
        // but most consumers just need "something changed in <id>".
        let cb = guiStateGet("cb.change." + wParam)
        if cb != "" {
            callPtr(cb, "")
        }
        emit "0"
    }
    if msgInt == 312 {
        // WM_CTLCOLORSTATIC: wParam=HDC of label, lParam=HWND of label.
        // Set text + bg color, return a transparent-or-themed brush.
        let textHex = guiStateGet("ui.text.color")
        if textHex != "" {
            SetTextColor(wParam, _guiColorRefFromHex(textHex) + "")
            SetBkMode(wParam, "1")
        }
        let brush = guiStateGet("ui.window.brush")
        if brush != "" { emit brush }
        emit GetStockObject("5")
    }
    if msgInt == 307 {
        // WM_CTLCOLOREDIT
        let textHex = guiStateGet("ui.text.color")
        if textHex != "" { SetTextColor(wParam, _guiColorRefFromHex(textHex) + "") }
        let brush = guiStateGet("ui.window.brush")
        if brush != "" { emit brush }
    }
    if msgInt == 310 {
        // WM_CTLCOLORDLG
        let brush = guiStateGet("ui.window.brush")
        if brush != "" { emit brush }
    }
    emit DefWindowProcA(hwnd, msg, wParam, lParam)
}

// 2026-05-11 Phase D: pure-Krypton guiInit. Registers a window class
// "PureKWnd" with our trampoline as lpfnWndProc, calls
// InitCommonControlsEx with the full set of common-control classes.
// Idempotent via guiState flag. SetUiFont / dark-mode / themes are
// separate calls now (user opts in explicitly).
func guiInit() {
    if guiStateGet("__krk_inited") == "1" { emit "1" }
    let icc = bufNew("8")
    bufSetDwordAt(icc, "0", "8")
    bufSetDwordAt(icc, "4", "20479")
    InitCommonControlsEx(icc)
    setWindowProc(funcptr(_krkWndProc))
    let hInst = GetModuleHandleA("0")
    let arrow = LoadCursorA("0", "32512")
    let className = "PureKWnd"
    let wcx = bufNew("80")
    bufSetDwordAt(wcx, "0", "80")
    bufSetDwordAt(wcx, "4", "3")
    bufSetQwordAt(wcx, "8", windowProcAddr())
    bufSetQwordAt(wcx, "24", hInst)
    bufSetQwordAt(wcx, "40", arrow)
    bufSetQwordAt(wcx, "48", "6")
    bufSetQwordAt(wcx, "64", ptrToInt(className))
    RegisterClassExA(wcx)
    guiStateSet("__krk_inited", "1")
    emit "1"
}
// 2026-05-11 Phase B: cfunc krGuiWindow returns hwnd as "0x%llx" hex,
// which __user_rt_atoi reads as 0 (atoi stops at the 'x'). All
// pure-Krypton ports calling Win32 with an int-marshalled HWND need
// a decimal version. Helper below + guiWindow now publishes both
// the original (kept for cfunc consumers) AND a decimal copy for
// the pure-Krypton ports to read.
// 2026-05-11 Phase D: parse decimal-or-hex. Returns int. Hex requires
// "0x"/"0X" prefix; bare digits parse as decimal so pure-Krypton
// guiWindow (which returns decimal hwnd) round-trips cleanly.
func _guiHexToInt(s) {
    if !startsWith(s, "0x") && !startsWith(s, "0X") {
        emit toInt(s)
    }
    let p = substring(s, 2, len(s))
    let v = 0
    let i = 0
    while i < len(p) {
        let c = charCode(p[i])
        let d = 0
        if c >= 48 && c <= 57  { d = c - 48 }
        if c >= 65 && c <= 70  { d = c - 55 }
        if c >= 97 && c <= 102 { d = c - 87 }
        v = v * 16 + d
        i = i + 1
    }
    emit v
}
// 2026-05-11 Phase D: pure-Krypton guiWindow. Uses the "PureKWnd" class
// registered by guiInit (lpfnWndProc = our trampoline). Returns the
// hwnd as a hex-prefixed string for backward compat with cfunc callers
// that may sscanf("%p", ...); _guiResolveHwnd already handles both
// formats. Pure-Krypton ports read decimal from guiStateGet("main.hwnd").
func guiWindow(title, w, h) {
    guiInit()
    let hInst = GetModuleHandleA("0")
    let hwnd = CreateWindowExA("0", "PureKWnd", title, "13565952", "100", "100", w + "", h + "", "0", "0", hInst, "0")
    guiStateSet("main.hwnd", hwnd)
    emit hwnd
}
// 2026-05-11 Phase B ports — pure Krypton via head:user32.
// SW_SHOW=5, SW_HIDE=0. krGuiWindow/Button/etc return hex-formatted
// hwnd strings ("0x..."); we hex-decode for the int-marshalled call.
func guiShow(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    ShowWindow(h, "5")
    UpdateWindow(h)
    emit "1"
}
func guiHide(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    ShowWindow(h, "0")
    emit "1"
}
// 2026-05-11 Phase D: "BUTTON" class, WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON = 1342242816.
func guiButton(parent, label, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "BUTTON", label, "1342242816", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D port — pure Krypton via CreateWindowExA.
// STATIC class, WS_CHILD(0x40000000) | WS_VISIBLE(0x10000000) | SS_LEFT(0) = 0x50000000 = 1342177280.
// Returns the child id as a decimal string; the cfunc returned an int
// id (not a hex hwnd) too, so this matches caller expectations.
func _guiNextId() {
    let cur = guiStateGet("__krk_next_id")
    let n = 1000
    if cur != "" { n = toInt(cur) }
    guiStateSet("__krk_next_id", (n + 1) + "")
    emit n + ""
}
func guiLabel(parent, text, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "STATIC", text, "1342177280", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// "EDIT" class, single-line. Style = WS_CHILD|WS_VISIBLE|WS_TABSTOP|ES_AUTOHSCROLL = 1342242944.
// dwExStyle = WS_EX_CLIENTEDGE (512) for the sunken border.
func guiTextInput(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("512", "EDIT", "", "1342242944", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// "EDIT" multi-line. WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_VSCROLL|ES_MULTILINE|ES_AUTOVSCROLL|ES_WANTRETURN = 1344606276.
func guiTextArea(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("512", "EDIT", "", "1344606276", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D: RichEdit needs msftedit.dll loaded so the
// RICHEDIT50W window class is registered. We lazy-load once per
// program; the state flag prevents repeat LoadLibrary calls.
// Style: WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|
//        ES_AUTOVSCROLL|ES_AUTOHSCROLL|ES_NOHIDESEL|ES_WANTRETURN = 1345749956.
func guiRichEdit(parent, x, y, w, h) {
    if guiStateGet("__krk_re_loaded") == "" {
        LoadLibraryA("msftedit.dll")
        guiStateSet("__krk_re_loaded", "1")
    }
    let pHwnd = _guiResolveHwnd(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "RICHEDIT50W", "", "1345749956", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D: CHARFORMATA struct (60 B on x64).
//   +0 cbSize(4) +4 dwMask +8 dwEffects +12 yHeight +16 yOffset
//   +20 crTextColor +24 bCharSet +25 bPitchAndFamily +26 szFaceName[32]
// EM_SETCHARFORMAT=1092. SCF_DEFAULT=0, SCF_SELECTION=1. CFM_BOLD=1,
// CFM_COLOR=0x40000000, combined=1073741825. EM_SETSEL=177, EM_REPLACESEL=194, WM_GETTEXTLENGTH=14.
func _krkCharFormat(mask, effects, color) {
    let cf = bufNew("60")
    bufSetDwordAt(cf, "0", "60")
    bufSetDwordAt(cf, "4", mask)
    bufSetDwordAt(cf, "8", effects)
    bufSetDwordAt(cf, "20", color)
    emit cf
}
func guiRichSetFmt(rich, start, end, hexColor, bold) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    SendMessageA(h, "177", start + "", end + "")
    let eff = "0"
    if bold != "0" && bold != "" { eff = "1" }
    let cf = _krkCharFormat("1073741825", eff, _guiColorRefFromHex(hexColor) + "")
    SendMessageA(h, "1092", "1", ptrToInt(cf))
    emit "1"
}
func guiRichClearFmt(rich) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let cf = _krkCharFormat("1073741825", "0", "0")
    SendMessageA(h, "1092", "1", ptrToInt(cf))
    emit "1"
}
func guiRichAppend(rich, text, hexColor, bold) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let oldLen = SendMessageA(h, "14", "0", "0")
    SendMessageA(h, "177", oldLen, oldLen)
    SendMessageA(h, "194", "0", ptrToInt(text))
    let newLen = SendMessageA(h, "14", "0", "0")
    SendMessageA(h, "177", oldLen, newLen)
    let eff = "0"
    if bold != "0" && bold != "" { eff = "1" }
    let cf = _krkCharFormat("1073741825", eff, _guiColorRefFromHex(hexColor) + "")
    SendMessageA(h, "1092", "1", ptrToInt(cf))
    emit "1"
}
// EM_SETREADONLY=207. Pure Krypton.
func guiRichReadOnly(rich, on) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let v = "0"
    if on != "0" && on != "" { v = "1" }
    SendMessageA(h, "207", v, "0")
    emit "1"
}
// 2026-05-11 Phase B: LOGFONTA struct (60 bytes on x64):
//   +0  lfHeight LONG (negative = height-in-pixels)
//   +4  lfWidth  LONG
//   +8  lfEscapement LONG
//   +12 lfOrientation LONG
//   +16 lfWeight LONG (FW_NORMAL=400)
//   +20 lfItalic BYTE
//   +21 lfUnderline BYTE
//   +22 lfStrikeOut BYTE
//   +23 lfCharSet BYTE (DEFAULT_CHARSET=1)
//   +24 lfOutPrecision BYTE
//   +25 lfClipPrecision BYTE
//   +26 lfQuality BYTE (CLEARTYPE_QUALITY=5)
//   +27 lfPitchAndFamily BYTE (FIXED_PITCH=1 | FF_DONTCARE=0 = 1)
//   +28 lfFaceName[32] CHAR (null-terminated)
// WM_SETFONT=48 (0x30), wParam=HFONT, lParam=fRedraw.
func guiRichSetMonoFont(rich, family, ptSize) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let lf = bufNew("60")
    let neg = 0 - toInt(ptSize)
    bufSetDwordAt(lf, "0", neg + "")
    bufSetDwordAt(lf, "16", "400")
    bufSetByte(lf, "23", "1")
    bufSetByte(lf, "26", "5")
    bufSetByte(lf, "27", "1")
    let i = 0
    while i < len(family) {
        if i < 31 {
            bufSetByte(lf, 28 + i, charCode(family[i]))
        }
        i = i + 1
    }
    let hf = CreateFontIndirectA(lf)
    SendMessageA(h, "48", hf, "1")
    emit "1"
}
// EM_SETBKGNDCOLOR=1097 (0x449). wParam=0 → use lParam as COLORREF.
// hexColor format: "0xRRGGBB" → COLORREF (0x00BBGGRR byte order).
func _guiColorRefFromHex(hex) {
    let v = _guiHexToInt(hex)
    let r = bitAnd(bitShr(v, "16"), "255")
    let g = bitAnd(bitShr(v, "8"), "255")
    let b = bitAnd(v, "255")
    emit bitOr(r, bitOr(bitShl(g, "8"), bitShl(b, "16")))
}
func guiRichSetBg(rich, hexColor) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let cr = _guiColorRefFromHex(hexColor)
    SendMessageA(h, "1097", "0", cr + "")
    emit "1"
}
// EM_SETCHARFORMAT with SCF_DEFAULT(0), CFM_COLOR(0x40000000) only.
func guiRichSetFgDefault(rich, hexColor) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    let cf = _krkCharFormat("1073741824", "0", _guiColorRefFromHex(hexColor) + "")
    SendMessageA(h, "1092", "0", ptrToInt(cf))
    emit "1"
}
// WM_SETREDRAW=11. wParam=0 to disable, =1 to enable. Pure Krypton.
func guiRichBeginUpdate(rich) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    SendMessageA(h, "11", "0", "0")
    emit "1"
}
func guiRichEndUpdate(rich) {
    let h = _guiResolveHwnd(rich)
    if h == "0" { emit "0" }
    SendMessageA(h, "11", "1", "0")
    InvalidateRect(h, "0", "1")
    emit "1"
}
// "BUTTON" class with BS_AUTOCHECKBOX style = 1342242819.
func guiCheckbox(parent, label, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "BUTTON", label, "1342242819", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase B SendMessageA-based ports (pure Krypton, no cfunc).
// BM_GETCHECK=240 → returns 1 if checked. BM_SETCHECK=241 (wParam=1/0).
func guiIsChecked(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    let r = SendMessageA(h, "240", "0", "0")
    if r == "1" { emit "1" }
    emit "0"
}
func guiSetChecked(hwnd, on) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    let v = "0"
    if on != "0" && on != "" { v = "1" }
    SendMessageA(h, "241", v, "0")
    emit "1"
}
// "LISTBOX" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_VSCROLL|WS_BORDER|LBS_NOTIFY = 1352663041.
func guiListbox(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "LISTBOX", "", "1352663041", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase B: LB_ADDSTRING=384, lParam=LPCSTR. The
// SendMessageA marshalling atoi's all 4 args, so we pre-convert the
// Krypton string `item` to its decimal address via ptrToInt (whose
// runtime stub was fixed earlier this session to JMP→__rt_itoa); the
// atoi at the call site decodes it back to the same address. Win32
// reads from that address as ANSI text. Pure Krypton.
func guiListAdd(hwnd, item) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    SendMessageA(h, "384", "0", ptrToInt(item))
    emit "1"
}
// LB_RESETCONTENT=388, LB_GETCURSEL=392. Pure Krypton.
func guiListClear(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    SendMessageA(h, "388", "0", "0")
    emit "1"
}
func guiListSelected(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "-1" }
    emit SendMessageA(h, "392", "0", "0")
}
// "msctls_progress32" class. WS_CHILD|WS_VISIBLE = 1342177280.
func guiProgress(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "msctls_progress32", "", "1342177280", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// PBM_SETPOS=1026 (msg + wParam=percent). Pure Krypton.
func guiProgressSet(hwnd, percent) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    SendMessageA(h, "1026", percent + "", "0")
    emit "1"
}
// "SysTreeView32" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|TVS_HASBUTTONS|TVS_HASLINES|TVS_LINESATROOT|TVS_SHOWSELALWAYS = 1350631463.
func guiTreeView(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "SysTreeView32", "", "1350631463", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D: TVINSERTSTRUCT (72 B on x64).
//   +0  HTREEITEM hParent
//   +8  HTREEITEM hInsertAfter  (TVI_LAST = -65534)
//   +16 TVITEMA (56 B) at this offset:
//        +16 mask  +24 hItem (ignored on insert)
//        +32 state, stateMask  +40 pszText  +48 cchTextMax, iImage
//        +56 iSelectedImage, cChildren  +64 lParam
// TVI_ROOT = -65536 (when parent_item is empty/"0"). TVM_INSERTITEMA = 4352.
// TVIF_TEXT = 1.
func _krkTreeInsert(tree, parent_item, label) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "" }
    let tvi = bufNew("72")
    let parentVal = parent_item
    if parent_item == "" { parentVal = "-65536" }
    if parent_item == "0" { parentVal = "-65536" }
    bufSetQwordAt(tvi, "0", parentVal)
    bufSetQwordAt(tvi, "8", "-65534")
    bufSetDwordAt(tvi, "16", "1")
    bufSetQwordAt(tvi, "40", ptrToInt(label))
    emit SendMessageA(h, "4352", "0", ptrToInt(tvi))
}
func guiTreeAdd(tree, parent_item, label)    { emit _krkTreeInsert(tree, parent_item, label) }
func guiTreeAddDir(tree, parent_item, label) { emit _krkTreeInsert(tree, parent_item, label) }
// 2026-05-11 Phase B: TVM_DELETEITEM=4360 with item=TVI_ROOT (0xFFFF0000).
// TVI_ROOT is a magic HTREEITEM constant. SendMessageA marshalling atois
// all 4 args, so we pass the constant as its decimal form.
func guiTreeClear(tree) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "0" }
    SendMessageA(h, "4360", "0", "4294901760")  // TVI_ROOT = 0xFFFF0000
    emit "1"
}
// 2026-05-11 Phase B: TVM_EXPAND=4354, TVE_EXPAND=2. `item` is a hex
// HTREEITEM string from cfunc (krGuiTreeAdd returns "0x..."); we
// hex-decode for the int-marshalled call. Pure Krypton.
func guiTreeExpand(tree, item) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "" }
    let it = _guiHexToInt(item)
    SendMessageA(h, "4354", "2", it + "")
    emit ""
}
// TVM_GETNEXTITEM=4362 (TV_FIRST+10). TVGN_CARET=9. Returns HTREEITEM as int string.
func guiTreeSelectedHandle(tree) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "" }
    let hItem = SendMessageA(h, "4362", "9", "0")
    if hItem == "0" { emit "" }
    emit hItem
}
// TVM_GETITEMA=4364 (TV_FIRST+12). Reads selected item's label via TVITEM:
//   +0 mask=TVIF_TEXT(1) +8 hItem +24 pszText=buf +32 cchTextMax=260
func guiTreeSelected(tree) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "" }
    let hItem = SendMessageA(h, "4362", "9", "0")
    if hItem == "0" { emit "" }
    let buf = bufNew("260")
    let item = bufNew("56")
    bufSetDwordAt(item, "0", "1")
    bufSetQwordAt(item, "8", hItem)
    bufSetQwordAt(item, "24", ptrToInt(buf))
    bufSetDwordAt(item, "32", "260")
    SendMessageA(h, "4364", "0", ptrToInt(item))
    emit _guiBufToStr(buf, 260)
}
// "SysTabControl32" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_CLIPSIBLINGS = 1409351680.
func guiTabs(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "SysTabControl32", "", "1409351680", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D: TCITEM struct (40 bytes on x64).
//   +0  UINT mask    +8 DWORD dwState   +12 DWORD dwStateMask
//   +16 LPSTR pszText  +24 int cchTextMax  +28 int iImage
//   +32 LPARAM lParam
// TCIF_TEXT=1. TCM_GETITEMCOUNT=4868. TCM_INSERTITEMA=4871.
func guiTabAdd(tabs, label) {
    let h = _guiResolveHwnd(tabs)
    if h == "0" { emit "-1" }
    let item = bufNew("40")
    bufSetDwordAt(item, "0", "1")
    bufSetQwordAt(item, "16", ptrToInt(label))
    let count = SendMessageA(h, "4868", "0", "0")
    SendMessageA(h, "4871", count, ptrToInt(item))
    emit count
}
// 2026-05-11 Phase B: TCM_SETCURSEL=4876, TCM_GETCURSEL=4875. Pure Krypton.
func guiTabSelect(tabs, idx) {
    let h = _guiResolveHwnd(tabs)
    if h == "0" { emit "-1" }
    emit SendMessageA(h, "4876", idx + "", "0")
}
// 2026-05-11 Phase D: enumerate tabs with TCM_GETITEMA=4869, compare labels.
// TCITEM layout same as guiTabAdd. Returns the 0-based index, or "-1" on miss.
func guiTabFind(tabs, label) {
    let h = _guiResolveHwnd(tabs)
    if h == "0" { emit "-1" }
    let count = toInt(SendMessageA(h, "4868", "0", "0"))
    let textBuf = bufNew("256")
    let item = bufNew("40")
    let i = 0
    while i < count {
        bufSetByte(textBuf, "0", "0")
        bufSetDwordAt(item, "0", "1")
        bufSetQwordAt(item, "16", ptrToInt(textBuf))
        bufSetDwordAt(item, "24", "256")
        SendMessageA(h, "4869", i + "", ptrToInt(item))
        let got = _guiBufToStr(textBuf, 256)
        if got == label { emit i + "" }
        i = i + 1
    }
    emit "-1"
}
func guiTabSelected(tabs) {
    let h = _guiResolveHwnd(tabs)
    if h == "0" { emit "-1" }
    emit SendMessageA(h, "4875", "0", "0")
}
// 2026-05-11 Phase D: WM_NOTIFY callback registry. `hwnd` is the control id
// (decimal); _krkWndProc reads wParam (idFrom) on WM_NOTIFY and looks up here.
func guiOnChange(hwnd, sinkPtr) {
    guiStateSet("cb.change." + hwnd, sinkPtr)
    emit "1"
}
// 2026-05-11 Phase D: Menu construction via CreateMenu + AppendMenuA.
// guiMenuBegin returns the HMENU of a fresh menubar attached to `window`.
// guiMenu(menubar, label) creates a popup, appends it to menubar, returns HMENU.
// guiMenuItem(popup, label) appends a clickable item with auto-allocated id.
// guiMenuSeparator(popup) appends a separator.
// guiMenuAdd is an alias for guiMenuItem.
// MF_STRING=0x0000, MF_POPUP=0x0010, MF_SEPARATOR=0x0800.
func guiMenuBegin(window) {
    let hw = _guiResolveHwnd(window)
    let menubar = CreateMenu()
    SetMenu(hw, menubar)
    DrawMenuBar(hw)
    emit menubar
}
func guiMenu(menubar, label) {
    let popup = CreatePopupMenu()
    AppendMenuA(menubar, "16", popup, label)
    emit popup
}
func guiMenuItem(popup, label) {
    let id = _guiNextId()
    AppendMenuA(popup, "0", id, label)
    emit id
}
func guiMenuSeparator(popup) {
    AppendMenuA(popup, "2048", "0", "0")
    emit ""
}
func guiMenuAdd(menu, label) {
    let id = _guiNextId()
    AppendMenuA(menu, "0", id, label)
    emit id
}
// "msctls_statusbar32" class. WS_CHILD|WS_VISIBLE|SBARS_SIZEGRIP(0x100) = 1342177536.
// 0 dims → auto-positioned by Win32.
func guiStatusBar(window) {
    let pHwnd = _guiHexToInt(window)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "msctls_statusbar32", "", "1342177536", "0", "0", "0", "0", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase B: SB_SETPARTS=1028 (0x404). lParam = LPINT (int*).
// Cap at 16 parts (rare apps need more).
func guiStatusParts(bar, widthsCsv) {
    let h = _guiResolveHwnd(bar)
    if h == "0" { emit "0" }
    let widths = split(widthsCsv, ",")
    let n = lineCount(widths)
    if n > 16 { n = 16 }
    let buf = bufNew("64")  // 16 * 4 bytes max
    let i = 0
    while i < n {
        let w = toInt(getLine(widths, i))
        bufSetDwordAt(buf, i * 4, w + "")
        i = i + 1
    }
    SendMessageA(h, "1028", n + "", ptrToInt(buf))
    emit ""
}
// 2026-05-11 Phase B: SB_SETTEXTA=1025 (0x401), SB_GETTEXTA=1026 (0x402).
// wParam packs the part index with style flags in the high byte; for the
// default "no border" path we just pass `idx` (no flags).
// SB_GETTEXTA's lParam is an output buffer; cfunc reads back via that buf.
func guiStatusSet(bar, idx, text) {
    let h = _guiResolveHwnd(bar)
    if h == "0" { emit "0" }
    SendMessageA(h, "1025", idx + "", ptrToInt(text))
    emit "1"
}
func guiStatusGet(bar, idx) {
    let h = _guiResolveHwnd(bar)
    if h == "0" { emit "" }
    let buf = bufNew("256")
    SendMessageA(h, "1026", idx + "", ptrToInt(buf))
    emit _guiBufToStr(buf, 256)
}
// 2026-05-11 Phase D: SB_SETICON=1039 (WM_USER+15). LoadImageA(NULL, name,
// IMAGE_ICON=1, 16x16, LR_LOADFROMFILE=16). wParam=part index, lParam=HICON.
func guiStatusIcon(bar, idx, iconName) {
    let h = _guiResolveHwnd(bar)
    if h == "0" { emit "0" }
    let hIcon = LoadImageA("0", iconName, "1", "16", "16", "16")
    if hIcon == "0" { emit "0" }
    SendMessageA(h, "1039", idx + "", hIcon)
    emit "1"
}
// SB_SETBKCOLOR=1025 (WM_USER+1). wParam=0, lParam=COLORREF.
func guiStatusBgColor(bar, hex) {
    let h = _guiResolveHwnd(bar)
    if h == "0" { emit "0" }
    let cr = _guiColorRefFromHex(hex)
    SendMessageA(h, "1025", "0", cr + "")
    emit "1"
}
// 2026-05-11 Phase D: Image widget = STATIC with SS_BITMAP, populated
// via LoadImageA. SS_BITMAP=14, so style = WS_CHILD|WS_VISIBLE|SS_BITMAP = 1342177294.
// LR_LOADFROMFILE=0x10=16. STM_SETIMAGE=370 (0x172) with IMAGE_BITMAP=0.
func guiImage(parent, path, x, y, w, h) {
    let pHwnd = _guiResolveHwnd(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "STATIC", "", "1342177294", x + "", y + "", w + "", h + "", pHwnd, id, hInst, "0")
    if ctl == "0" { emit "0" }
    let himg = LoadImageA("0", path, "0", "0", "0", "16")
    if himg != "0" {
        SendMessageA(ctl, "370", "0", himg)
    }
    emit id
}
func guiImageSet(image, path) {
    let h = _guiResolveHwnd(image)
    if h == "0" { emit "0" }
    let himg = LoadImageA("0", path, "0", "0", "0", "16")
    if himg == "0" { emit "0" }
    SendMessageA(h, "370", "0", himg)
    emit "1"
}

// ── Layout stacks ────────────────────────────────────────────
//
// Vertical stack: pin x + width, walk widgets down the y axis.
// Horizontal stack: pin y + height, walk widgets across x.
//
// guiV* / guiH* helpers below take a stack and the per-widget cross
// size (height in V, width in H) and slot the widget in at the next
// cursor position. Each returns the same handle/id as its non-stack
// counterpart so guiOnClick / guiGetText / etc. work normally.

// 2026-05-11 Phase B: MoveWindow direct. Pure Krypton.
func guiMove(handle, x, y, w, h) {
    let H = _guiResolveHwnd(handle)
    if H == "0" { emit "0" }
    MoveWindow(H, x + "", y + "", w + "", h + "", "1")
    emit "1"
}
// 2026-05-11 Phase D: pure-Krypton dock layout. State per dock:
//   dock.<id>.win — parent hwnd
//   dock.<id>.q   — newline-joined queue of "side|hwnd|size" entries
// guiDockApply walks the queue, calculates positions from GetClientRect,
// MoveWindows each child. RECT layout: left(4) top(4) right(4) bottom(4).
func guiDock(window) {
    let id = _guiNextId()
    guiStateSet("dock." + id + ".win", window)
    guiStateSet("dock." + id + ".q", "")
    emit id
}
func _krkDockAppend(dock, side, hwnd, size) {
    let cur = guiStateGet("dock." + dock + ".q")
    let entry = side + "|" + hwnd + "|" + size
    if cur == "" {
        guiStateSet("dock." + dock + ".q", entry)
    } else {
        guiStateSet("dock." + dock + ".q", cur + "\n" + entry)
    }
}
func guiDockTop(dock, hwnd, size)    { _krkDockAppend(dock, "T", hwnd, size + "")  emit "" }
func guiDockBottom(dock, hwnd, size) { _krkDockAppend(dock, "B", hwnd, size + "")  emit "" }
func guiDockLeft(dock, hwnd, size)   { _krkDockAppend(dock, "L", hwnd, size + "")  emit "" }
func guiDockRight(dock, hwnd, size)  { _krkDockAppend(dock, "R", hwnd, size + "")  emit "" }
func guiDockFill(dock, hwnd)         { _krkDockAppend(dock, "F", hwnd, "0")  emit "" }
func guiDockApply(dock) {
    let window = guiStateGet("dock." + dock + ".win")
    let win = _guiResolveHwnd(window)
    let rect = bufNew("16")
    GetClientRect(win, rect)
    let top = 0
    let left = 0
    let right = toInt(bufGetDwordAt(rect, "8"))
    let bottom = toInt(bufGetDwordAt(rect, "12"))
    let q = guiStateGet("dock." + dock + ".q")
    if q == "" { emit "" }
    let lc = lineCount(q)
    let i = 0
    while i < lc {
        let line = getLine(q, i)
        let parts = split(line, "|")
        let side = getLine(parts, 0)
        let hwnd = getLine(parts, 1)
        let size = toInt(getLine(parts, 2))
        let h = _guiResolveHwnd(hwnd)
        if side == "T" {
            MoveWindow(h, left + "", top + "", (right - left) + "", size + "", "1")
            top = top + size
        }
        if side == "B" {
            bottom = bottom - size
            MoveWindow(h, left + "", bottom + "", (right - left) + "", size + "", "1")
        }
        if side == "L" {
            MoveWindow(h, left + "", top + "", size + "", (bottom - top) + "", "1")
            left = left + size
        }
        if side == "R" {
            right = right - size
            MoveWindow(h, right + "", top + "", size + "", (bottom - top) + "", "1")
        }
        if side == "F" {
            MoveWindow(h, left + "", top + "", (right - left) + "", (bottom - top) + "", "1")
        }
        i = i + 1
    }
    emit ""
}
// 2026-05-11 Phase D: visual splitter via STATIC + SS_ETCHEDHORZ/VERT.
// Drag-resize behavior deferred (needs WindowProc subclass for WM_MOUSEMOVE).
// Position is stored in state and returned by guiSplitterPos as-set.
// SS_ETCHEDHORZ=16, SS_ETCHEDVERT=17.
func guiSplitter(parent, x, y, w, h, orientation) {
    let pHwnd = _guiResolveHwnd(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let vert = "0"
    if startsWith(orientation, "v") { vert = "1" }
    if startsWith(orientation, "V") { vert = "1" }
    let style = "1342177296"
    if vert == "1" { style = "1342177297" }
    let ctl = CreateWindowExA("0", "STATIC", "", style, x + "", y + "", w + "", h + "", pHwnd, id, hInst, "0")
    if ctl == "0" { emit "0" }
    if vert == "1" {
        guiStateSet("split." + id, x + "")
    } else {
        guiStateSet("split." + id, y + "")
    }
    emit id
}
func guiSplitterPos(splitter) {
    let p = guiStateGet("split." + splitter)
    if p == "" { emit "0" }
    emit p
}
// "COMBOBOX" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_VSCROLL|CBS_DROPDOWNLIST(3) = 1344602115.
func guiCombo(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "COMBOBOX", "", "1344602115", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// CB_ADDSTRING=323. Same lParam=LPCSTR trick as guiListAdd.
func guiComboAdd(combo, item) {
    let h = _guiResolveHwnd(combo)
    if h == "0" { emit "0" }
    SendMessageA(h, "323", "0", ptrToInt(item))
    emit "1"
}
// 2026-05-11 Phase B: combo SendMessage ports. Pure Krypton.
// CB_RESETCONTENT=331, CB_GETCURSEL=327, CB_SETCURSEL=334.
func guiComboClear(combo) {
    let h = _guiResolveHwnd(combo)
    if h == "0" { emit "0" }
    SendMessageA(h, "331", "0", "0")
    emit "1"
}
func guiComboSelected(combo) {
    let h = _guiResolveHwnd(combo)
    if h == "0" { emit "-1" }
    emit SendMessageA(h, "327", "0", "0")
}
func guiComboSet(combo, idx) {
    let h = _guiResolveHwnd(combo)
    if h == "0" { emit "0" }
    SendMessageA(h, "334", idx + "", "0")
    emit "1"
}
// 2026-05-11 Phase B port — pure Krypton, no cfunc.
// CHOOSECOLORA struct (72 bytes on x64):
//   +0  DWORD lStructSize (72)
//   +8  HWND  hwndOwner
//   +24 COLORREF rgbResult (0x00BBGGRR byte order)
//   +32 DWORD* lpCustColors  (→ 16 DWORDs)
//   +40 DWORD Flags = CC_FULLOPEN(2) | CC_RGBINIT(1) | CC_ANYCOLOR(0x100) = 259
// Initial-color parsing intentionally omitted (the caller's previous
// "0xRRGGBB" tag isn't trivially scannable in pure Krypton until we
// have hex parsing in stdlib; user re-picks from black until that
// lands). Returns "0xRRGGBB" or "" on cancel — matches the cfunc API.
func _guiHexNibble(n) {
    if n < 10 { emit fromCharCode(48 + n + "") }
    emit fromCharCode(55 + n + "")
}
func _guiHexByte(b) {
    let hi = b / 16
    let lo = b % 16
    emit _guiHexNibble(hi) + _guiHexNibble(lo)
}
func guiColorPicker(initialHex) {
    let hwnd = guiStateGet("main.hwnd")
    let cc = bufNew("72")
    bufSetDwordAt(cc, "0", "72")
    if hwnd != "" { bufSetQwordAt(cc, "8", hwnd) }
    let custom = bufNew("64")
    bufSetQwordAt(cc, "32", ptrToInt(custom))
    bufSetDwordAt(cc, "40", "259")
    let ok = ChooseColorA(cc)
    if ok == "0" { emit "" }
    let v = bufGetDwordAt(cc, "24")
    let r = bitAnd(v, "255")
    let g = bitAnd(bitShr(v, "8"), "255")
    let b = bitAnd(bitShr(v, "16"), "255")
    emit "0x" + _guiHexByte(r) + _guiHexByte(g) + _guiHexByte(b)
}
// "SysDateTimePick32" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|DTS_SHORTDATEFORMAT(0) = 1342242816.
func guiDatePicker(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "SysDateTimePick32", "", "1342242816", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase D: SYSTEMTIME (16 bytes) struct dispatch.
//   +0 wYear (2)    +2 wMonth (2)   +4 wDOW (2)    +6 wDay (2)
//   +8 wHour (2)    +10 wMinute (2) +12 wSec (2)   +14 wMs (2)
// DTM_GETSYSTEMTIME=4097 (wParam=0, lParam=ptr). DTM_SETSYSTEMTIME=4098 (wParam=GDT_VALID=0).
func _krk2d(n) {
    let s = n + ""
    if len(s) < 2 { emit "0" + s }
    emit s
}
func guiDateGet(picker) {
    let h = _guiResolveHwnd(picker)
    if h == "0" { emit "" }
    let st = bufNew("16")
    SendMessageA(h, "4097", "0", ptrToInt(st))
    let year = bufGetWordAt(st, "0")
    let month = bufGetWordAt(st, "2")
    let day = bufGetWordAt(st, "6")
    emit year + "-" + _krk2d(month) + "-" + _krk2d(day)
}
func guiDateSet(picker, ymd) {
    let h = _guiResolveHwnd(picker)
    if h == "0" { emit "0" }
    // ymd = "YYYY-MM-DD"
    let parts = split(ymd, "-")
    if lineCount(parts) < 3 { emit "0" }
    let st = bufNew("16")
    bufSetWordAt(st, "0", getLine(parts, 0))
    bufSetWordAt(st, "2", getLine(parts, 1))
    bufSetWordAt(st, "6", getLine(parts, 2))
    SendMessageA(h, "4098", "0", ptrToInt(st))
    emit "1"
}
// "SCROLLBAR" class. WS_CHILD|WS_VISIBLE|SBS_VERT(1)/SBS_HORZ(0).
func guiScrollbar(parent, x, y, w, h, vertical) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let style = "1342177280"
    if vertical != "0" && vertical != "" { style = "1342177281" }
    let ctl = CreateWindowExA("0", "SCROLLBAR", "", style, x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase B: scrollbar ports. SBM_SETPOS=224 (E0), SBM_GETPOS=225,
// SBM_SETRANGE=226 (228 SETRANGEREDRAW). Page size needs SBM_SETSCROLLINFO
// which takes a SCROLLINFO struct — for the simple cases we use the legacy
// SBM_SETRANGE which doesn't support page. Pass-through for SBM_SETSCROLLINFO
// path until SCROLLINFO struct construction lands as a follow-up.
// 2026-05-11 Phase D: SBM_SETSCROLLINFO=233. SCROLLINFO struct (28 bytes):
//   +0 cbSize=28  +4 fMask=3(SIF_RANGE|SIF_PAGE)  +8 nMin  +12 nMax  +16 nPage  +20 nPos  +24 nTrackPos
func guiScrollbarRange(sb, lo, hi, page) {
    let h = _guiResolveHwnd(sb)
    if h == "0" { emit "0" }
    let si = bufNew("28")
    bufSetDwordAt(si, "0", "28")
    bufSetDwordAt(si, "4", "3")
    bufSetDwordAt(si, "8", lo + "")
    bufSetDwordAt(si, "12", hi + "")
    bufSetDwordAt(si, "16", page + "")
    SendMessageA(h, "233", "1", ptrToInt(si))
    emit "1"
}
func guiScrollbarValue(sb) {
    let h = _guiResolveHwnd(sb)
    if h == "0" { emit "0" }
    emit SendMessageA(h, "225", "0", "0")
}
func guiScrollbarSet(sb, value) {
    let h = _guiResolveHwnd(sb)
    if h == "0" { emit "0" }
    SendMessageA(h, "224", value + "", "1")
    emit "1"
}
// 2026-05-11 Phase D: layout stacks ported to pure Krypton. Stack state
// is a CSV record stored under `stk.<id>` via guiStateSet/Get:
//   parent | x | y | size | gap | cursor | orient   (orient: 0=V, 1=H)
// VNext/HNext advance the cursor; consumers compute child position from cursor.
// guiStateSet/Get still cfunc-routed; eliminate when state helpers move out of cfunc.
func _krkStackField(stack, idx) {
    let s = guiStateGet("stk." + stack)
    let parts = split(s, "|")
    emit getLine(parts, idx)
}
func _krkStackUpdateCursor(stack, newCursor) {
    let s = guiStateGet("stk." + stack)
    let p = split(s, "|")
    let updated = getLine(p, 0) + "|" + getLine(p, 1) + "|" + getLine(p, 2) + "|" + getLine(p, 3) + "|" + getLine(p, 4) + "|" + newCursor + "|" + getLine(p, 6)
    guiStateSet("stk." + stack, updated)
}
func guiVStack(parent, x, y, width, gap) {
    let id = _guiNextId()
    guiStateSet("stk." + id, parent + "|" + (x + "") + "|" + (y + "") + "|" + (width + "") + "|" + (gap + "") + "|" + (y + "") + "|0")
    emit id
}
func guiHStack(parent, x, y, height, gap) {
    let id = _guiNextId()
    guiStateSet("stk." + id, parent + "|" + (x + "") + "|" + (y + "") + "|" + (height + "") + "|" + (gap + "") + "|" + (x + "") + "|1")
    emit id
}
func guiVNext(stack, height) {
    let cursor = toInt(_krkStackField(stack, "5"))
    let gap = toInt(_krkStackField(stack, "4"))
    _krkStackUpdateCursor(stack, (cursor + toInt(height + "") + gap) + "")
    emit cursor + ""
}
func guiHNext(stack, width) {
    let cursor = toInt(_krkStackField(stack, "5"))
    let gap = toInt(_krkStackField(stack, "4"))
    _krkStackUpdateCursor(stack, (cursor + toInt(width + "") + gap) + "")
    emit cursor + ""
}
func guiStackParent(stack)                       { emit _krkStackField(stack, "0") }
func guiStackX(stack)                            { emit _krkStackField(stack, "1") }
func guiStackY(stack)                            { emit _krkStackField(stack, "2") }
func guiStackW(stack)                            { emit _krkStackField(stack, "3") }
func guiStackH(stack)                            { emit _krkStackField(stack, "3") }
func guiVGap(stack, pixels) {
    let cursor = toInt(_krkStackField(stack, "5"))
    _krkStackUpdateCursor(stack, (cursor + toInt(pixels + "")) + "")
    emit ""
}
func guiHGap(stack, pixels) {
    let cursor = toInt(_krkStackField(stack, "5"))
    _krkStackUpdateCursor(stack, (cursor + toInt(pixels + "")) + "")
    emit ""
}

// ── V-stack convenience widgets ──────────────────────────────
// Each places a widget at the stack's next y, using the stack's
// fixed x + width. Returns the underlying handle/id.

func guiVLabel(stack, text, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiLabel(p, text, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVButton(stack, label, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiButton(p, label, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVInput(stack, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiTextInput(p, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVTextArea(stack, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiTextArea(p, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVCheckbox(stack, label, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiCheckbox(p, label, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVProgress(stack, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiProgress(p, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

func guiVSlider(stack, height) {
    let p = guiStackParent(stack)
    let y = guiVNext(stack, height)
    emit guiSlider(p, toInt(guiStackX(stack)), toInt(y), toInt(guiStackW(stack)), height)
}

// ── H-stack convenience widgets ──────────────────────────────
// Cross axis is height (set at stack creation). Per-widget size
// argument is the width.

func guiHLabel(stack, text, width) {
    let p = guiStackParent(stack)
    let x = guiHNext(stack, width)
    emit guiLabel(p, text, toInt(x), toInt(guiStackY(stack)), width, toInt(guiStackH(stack)))
}

func guiHButton(stack, label, width) {
    let p = guiStackParent(stack)
    let x = guiHNext(stack, width)
    emit guiButton(p, label, toInt(x), toInt(guiStackY(stack)), width, toInt(guiStackH(stack)))
}

func guiHInput(stack, width) {
    let p = guiStackParent(stack)
    let x = guiHNext(stack, width)
    emit guiTextInput(p, toInt(x), toInt(guiStackY(stack)), width, toInt(guiStackH(stack)))
}

func guiHCheckbox(stack, label, width) {
    let p = guiStackParent(stack)
    let x = guiHNext(stack, width)
    emit guiCheckbox(p, label, toInt(x), toInt(guiStackY(stack)), width, toInt(guiStackH(stack)))
}
// "msctls_trackbar32" class. WS_CHILD|WS_VISIBLE|WS_TABSTOP|TBS_AUTOTICKS(1) = 1342242817.
func guiSlider(parent, x, y, w, h) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "msctls_trackbar32", "", "1342242817", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    emit id
}
// 2026-05-11 Phase B: TBM_GETPOS=1024, TBM_SETPOS=1029, TBM_SETRANGE=1030.
// MAKELONG(lo,hi) = (hi<<16) | (lo & 0xFFFF). Pure Krypton.
func guiSliderRange(slider, lo, hi) {
    let h = _guiResolveHwnd(slider)
    if h == "0" { emit "0" }
    let packed = bitOr(bitAnd(lo + "", "65535"), bitShl(bitAnd(hi + "", "65535"), "16"))
    SendMessageA(h, "1030", "1", packed + "")
    emit "1"
}
func guiSliderSet(slider, value) {
    let h = _guiResolveHwnd(slider)
    if h == "0" { emit "0" }
    SendMessageA(h, "1029", "1", value + "")
    emit "1"
}
func guiSliderValue(slider) {
    let h = _guiResolveHwnd(slider)
    if h == "0" { emit "0" }
    emit SendMessageA(h, "1024", "0", "0")
}
// 2026-05-11 Phase D: spinbox = EDIT + UpDown paired via UDM_SETBUDDY.
// EDIT is the user-visible handle (returned id); UpDown is tracked via
// state `spinpair.<edit_id>` → updown_id. UDM_SETRANGE32=1135 (WM_USER+111).
// UDM_SETPOS32=1138 (WM_USER+114). UDM_GETPOS32=1140 (WM_USER+116).
// UDM_SETBUDDY=1129 (WM_USER+105).
// UpDown style: WS_CHILD|WS_VISIBLE|UDS_AUTOBUDDY(0x10)|UDS_SETBUDDYINT(0x2)|
//               UDS_ALIGNRIGHT(0x4)|UDS_ARROWKEYS(0x20) = 0x50000036 = 1342177334.
func guiSpinbox(parent, x, y, w, h) {
    let pHwnd = _guiResolveHwnd(parent)
    let hInst = GetModuleHandleA("0")
    let editId = _guiNextId()
    let edit = CreateWindowExA("512", "EDIT", "0", "1342242944", x + "", y + "", w + "", h + "", pHwnd, editId, hInst, "0")
    if edit == "0" { emit "0" }
    let upId = _guiNextId()
    let up = CreateWindowExA("0", "msctls_updown32", "", "1342177334", "0", "0", "0", "0", pHwnd, upId, hInst, "0")
    if up != "0" {
        SendMessageA(up, "1129", edit, "0")
        guiStateSet("spinpair." + editId, up)
    }
    emit editId
}
func guiSpinboxRange(spin, lo, hi) {
    let up = guiStateGet("spinpair." + spin)
    if up == "" { emit "0" }
    SendMessageA(up, "1135", lo + "", hi + "")
    emit "1"
}
func guiSpinboxSet(spin, value) {
    let up = guiStateGet("spinpair." + spin)
    if up == "" { emit "0" }
    SendMessageA(up, "1138", "0", value + "")
    emit "1"
}
func guiSpinboxValue(spin) {
    let up = guiStateGet("spinpair." + spin)
    if up == "" { emit "0" }
    emit SendMessageA(up, "1140", "0", "0")
}
// "ToolbarWindow32" class. WS_CHILD|WS_VISIBLE|TBSTYLE_FLAT(0x800)|TBSTYLE_TOOLTIPS(0x100)|CCS_NODIVIDER(0x40)|CCS_NOPARENTALIGN(0x8) = 1342179656.
// Sends TB_BUTTONSTRUCTSIZE=1054 with sizeof(TBBUTTON)=32 (x64 layout) so subsequent TB_ADDBUTTONS calls read the struct correctly.
func guiToolbar(window) {
    let pHwnd = _guiResolveHwnd(window)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "ToolbarWindow32", "", "1342179656", "0", "0", "0", "0", pHwnd, id, hInst, "0")
    if ctl == "0" { emit "0" }
    SendMessageA(ctl, "1054", "32", "0")
    emit id
}
// 2026-05-11 Phase D: TBBUTTON with iString as a string pointer.
// Win32 detects pointer mode by the high DWORD being non-zero (which is true
// for 64-bit heap/rdata addresses). iconName ignored for now — icon support
// needs ImageList integration (later port).
func guiToolButton(toolbar, label, iconName) {
    let h = _guiResolveHwnd(toolbar)
    if h == "0" { emit "0" }
    let id = _guiNextId()
    let btn = bufNew("32")
    bufSetDwordAt(btn, "4", id)
    bufSetByte(btn, "8", "4")
    bufSetByte(btn, "9", "0")
    bufSetQwordAt(btn, "24", ptrToInt(label))
    SendMessageA(h, "1044", "1", ptrToInt(btn))
    emit id
}
// 2026-05-11 Phase D: TB_ADDBUTTONS=1044 (WM_USER+20). TBBUTTON struct (32 B on x64):
//   +0 iBitmap (4)  +4 idCommand (4)
//   +8 fsState (1)  +9 fsStyle (1)  +10 pad[6]
//   +16 dwData (8)  +24 iString (8)
// Separator: fsState=TBSTATE_ENABLED(4), fsStyle=TBSTYLE_SEP(1).
func guiToolSep(toolbar) {
    let h = _guiResolveHwnd(toolbar)
    if h == "0" { emit "" }
    let btn = bufNew("32")
    bufSetByte(btn, "8", "4")
    bufSetByte(btn, "9", "1")
    SendMessageA(h, "1044", "1", ptrToInt(btn))
    emit ""
}
// 2026-05-11 Phase B: TB_GETBUTTONSIZE=1054. Returns packed DWORD with
// LOWORD=width, HIWORD=height. We extract the height (high 16 bits).
func guiToolbarHeight(toolbar) {
    let h = _guiResolveHwnd(toolbar)
    if h == "0" { emit "0" }
    let packed = SendMessageA(h, "1054", "0", "0")
    emit bitAnd(bitShr(packed, "16"), "65535")
}
// 2026-05-11 Phase B ports — pure Krypton, no cfunc.
//
// OPENFILENAMEA layout on x64 (current SDK with WINVER >= 0x0500 →
// includes pvReserved/dwReserved/FlagsEx ext block → 176 bytes total):
//   +0   DWORD  lStructSize
//   +8   HWND   hwndOwner
//   +24  LPCSTR lpstrFilter      (null-separated description/pattern pairs, double-null terminator)
//   +56  LPSTR  lpstrFile        (output buffer)
//   +64  DWORD  nMaxFile         (size of lpstrFile in chars)
//   +96  LPCSTR lpstrTitle
//   +104 DWORD  Flags
// Filter CSV format: "Krypton|*.k,All Files|*.*" (entries comma-separated, label-and-pattern pipe-separated).
func _guiFilterCopy(buf, pos, s) {
    let i = 0
    while i < len(s) {
        bufSetByte(buf, pos + i, charCode(s[i]))
        i = i + 1
    }
    bufSetByte(buf, pos + len(s), "0")
    emit pos + len(s) + 1
}
func _guiBuildFilter(csv) {
    let effective = csv
    if len(effective) == 0 { effective = "All Files|*.*" }
    let buf = bufNew("1024")
    let pos = 0
    let parts = split(effective, ",")
    let n = lineCount(parts)
    let i = 0
    while i < n {
        let entry = getLine(parts, i)
        let pipe = indexOf(entry, "|")
        let label = entry
        let pattern = entry
        if pipe >= 0 {
            label = substring(entry, 0, pipe)
            pattern = substring(entry, pipe + 1, len(entry))
        }
        pos = toInt(_guiFilterCopy(buf, pos, label))
        pos = toInt(_guiFilterCopy(buf, pos, pattern))
        i = i + 1
    }
    bufSetByte(buf, pos, "0")
    emit buf
}
func _guiBufToStr(buf, maxLen) {
    let sb = sbNew()
    let i = 0
    while i < maxLen {
        let b = toInt(bufGetByte(buf, i))
        if b == 0 { emit sbToString(sb) }
        sb = sbAppend(sb, fromCharCode(b))
        i = i + 1
    }
    emit sbToString(sb)
}
func guiOpenFile(title, filterCsv) {
    let hwnd = guiStateGet("main.hwnd")
    let ofn = bufNew("176")
    bufSetDwordAt(ofn, "0", "176")
    if hwnd != "" { bufSetQwordAt(ofn, "8", hwnd) }
    let filterBuf = _guiBuildFilter(filterCsv)
    bufSetQwordAt(ofn, "24", ptrToInt(filterBuf))
    let pathBuf = bufNew("2048")
    bufSetQwordAt(ofn, "56", ptrToInt(pathBuf))
    bufSetDwordAt(ofn, "64", "2048")
    let titleStr = title
    if len(titleStr) == 0 { titleStr = "Open File" }
    bufSetQwordAt(ofn, "96", ptrToInt(titleStr))
    // OFN_FILEMUSTEXIST(0x1000) | OFN_PATHMUSTEXIST(0x800) | OFN_HIDEREADONLY(0x4) | OFN_NOCHANGEDIR(0x8) = 6156
    bufSetDwordAt(ofn, "104", "6156")
    let ok = GetOpenFileNameA(ofn)
    if ok == "0" { emit "" }
    emit _guiBufToStr(pathBuf, 2048)
}
func guiSaveFile(title, filterCsv, defaultName) {
    let hwnd = guiStateGet("main.hwnd")
    let ofn = bufNew("176")
    bufSetDwordAt(ofn, "0", "176")
    if hwnd != "" { bufSetQwordAt(ofn, "8", hwnd) }
    let filterBuf = _guiBuildFilter(filterCsv)
    bufSetQwordAt(ofn, "24", ptrToInt(filterBuf))
    let pathBuf = bufNew("2048")
    if len(defaultName) > 0 {
        let _unused = _guiFilterCopy(pathBuf, 0, defaultName)
    }
    bufSetQwordAt(ofn, "56", ptrToInt(pathBuf))
    bufSetDwordAt(ofn, "64", "2048")
    let titleStr = title
    if len(titleStr) == 0 { titleStr = "Save File" }
    bufSetQwordAt(ofn, "96", ptrToInt(titleStr))
    // OFN_OVERWRITEPROMPT(0x2) | OFN_PATHMUSTEXIST(0x800) | OFN_HIDEREADONLY(0x4) | OFN_NOCHANGEDIR(0x8) = 2062
    bufSetDwordAt(ofn, "104", "2062")
    let ok = GetSaveFileNameA(ofn)
    if ok == "0" { emit "" }
    emit _guiBufToStr(pathBuf, 2048)
}
// 2026-05-11 Phase D: dynamic load of shell32 (avoids adding a 15th IAT
// DLL). BROWSEINFOA struct (64 bytes on x64):
//   +0 hwndOwner  +8 pidlRoot=NULL  +16 pszDisplayName=NULL
//   +24 lpszTitle  +32 ulFlags(4)  +40 lpfn=NULL  +48 lParam  +56 iImage
// BIF_RETURNONLYFSDIRS=1. SHBrowseForFolderA → LPITEMIDLIST. SHGetPathFromIDListA(pidl,buf)
// fills `buf` with the path. CoTaskMemFree(pidl) afterwards.
// Use ptrToInt for NULL-safe comparison (LoadLibraryA returns raw HMODULE).
func guiPickFolder(title) {
    let shell32 = LoadLibraryA("shell32.dll")
    if ptrToInt(shell32) == "0" { emit "" }
    let browse = GetProcAddress(shell32, "SHBrowseForFolderA")
    let getPath = GetProcAddress(shell32, "SHGetPathFromIDListA")
    if ptrToInt(browse) == "0" { emit "" }
    if ptrToInt(getPath) == "0" { emit "" }
    let bi = bufNew("64")
    let main = guiStateGet("main.hwnd")
    if main != "" { bufSetQwordAt(bi, "0", main) }
    bufSetQwordAt(bi, "24", ptrToInt(title))
    bufSetDwordAt(bi, "32", "1")
    let pidl = callPtr(browse, bi)
    if ptrToInt(pidl) == "0" { emit "" }
    let pathBuf = bufNew("260")
    callPtr(getPath, pidl, pathBuf)
    CoTaskMemFree(pidl)
    emit _guiBufToStr(pathBuf, 260)
}
// 2026-05-11 Phase B ports — pure Krypton via head:user32.
// Dispatch: "0x..."hex → direct HWND; bare-decimal id >= 1000 →
// GetDlgItem(main_hwnd, id) → HWND.  Matches the cfunc legacy dual-format.
// 2026-05-11 Phase D: dispatch hwnd format.
//   "0x..." → hex parse
//   decimal in [1000, 65535] → control id, look up via GetDlgItem(main_hwnd, id)
//   anything else (decimal > 65535) → direct hwnd
func _guiResolveHwnd(hwnd) {
    if startsWith(hwnd, "0x") || startsWith(hwnd, "0X") {
        emit _guiHexToInt(hwnd) + ""
    }
    let id = toInt(hwnd)
    if id >= 1000 && id <= 65535 {
        let main = guiStateGet("main.hwnd")
        if main != "" {
            emit GetDlgItem(main, hwnd)
        }
    }
    emit hwnd
}
func guiSetText(hwnd, text) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "0" }
    SetWindowTextA(h, text)
    emit "1"
}
func guiGetText(hwnd) {
    let h = _guiResolveHwnd(hwnd)
    if h == "0" { emit "" }
    let buf = bufNew("2048")
    GetWindowTextA(h, buf, "2048")
    emit _guiBufToStr(buf, 2048)
}
// 2026-05-11 Phase D: register a Krypton funcptr keyed by control id.
// _krkWndProc looks up "cb.click.<id>" on WM_COMMAND and invokes via callPtr.
// `hwnd` here is a control id (decimal, from widget creators), not a hex hwnd.
func guiOnClick(hwnd, sinkPtr) {
    guiStateSet("cb.click." + hwnd, sinkPtr)
    emit "1"
}
// Native pure-Krypton port (2026-05-11): MessageBoxA via user32 IAT
// (no longer routes through cfunc krGuiMessageBox / kr_gui_to_w UTF-16
// conversion). ANSI/MBCS only for now — true UTF-16 deferred until the
// rest of the cfunc body is ported and we can drop ANSI altogether.
// uType 64 = MB_OK | MB_ICONINFORMATION.
func guiMessageBox(title, msg)                   { emit MessageBoxA("0", msg, title, "64") }
// 2026-05-11 Phase B ports — pure Krypton message pump.
// MSG struct (x64): 48 bytes (hwnd@0, message@8, wParam@16, lParam@24,
// time@32, pt@40). GetMessageA returns 0 on WM_QUIT, -1 on error,
// >0 normally — Krypton compares the int-marshalled string forms.
// DispatchMessageA fans out to the WindowProc registered by the
// cfunc body's krGuiWindow; once the WindowProc itself is ported
// (Phase D), this entire pump runs free of any cfunc dependency.
func guiRun() {
    let msg = bufNew("48")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" && r != "-1" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }
    emit "0"
}
func guiQuit() {
    PostQuitMessage("0")
    emit "0"
}

// Shared state helpers — Krypton-side event handlers can stash
// strings here so other handlers can read them back. Since Krypton
// has no mutable module globals across function calls, this is the
// canonical workaround for IDE-style apps that need cross-handler
// state (current file path, dirty flag, etc.).
// 2026-05-11 Phase D: pure-Krypton state via rawalloc-backed kv store.
// The state buf is allocated via `kr_rawalloc` (HeapAlloc-backed, NOT
// Krypton-GC-tracked) so it persists for the program's lifetime. The buf
// address is tracked via process env var "KRK_STATE_BUF" as a decimal
// string. Keys are rawalloc-copied (so they survive Krypton GC of the
// caller's key string). Values are stored as raw 8-byte pointer values
// — matches cfunc krGuiStateSet semantics (no strdup on value).
//
// Layout in the rawalloc'd buf:
//   +0  qword count (number of entries used)
//   +8  entry[0]: 8-byte key_ptr (to rawalloc'd key copy) + 8-byte value_ptr
//   ...
// Capacity 256 entries (8 + 256*16 = 4104 bytes).
// NOTE: rt.dll's `kr_rawalloc` actually calls `__rt_alloc` (GC arena)
// not HeapAlloc, so its memory is still GC-tracked. We use Win32
// `HeapAlloc(GetProcessHeap(), 0, size)` directly via the kernel32 IAT
// — that memory is truly outside the GC and persists for the program's
// lifetime. HeapAlloc returns LPVOID as a raw 8-byte pointer (no itoa
// marshalling), so we use the result directly as a buf-base in
// subsequent `bufSetByte`/`bufSetQwordAt`.
func _krkStateBuf() {
    let buf = bufNew("64")
    let len = GetEnvironmentVariableA("KRK_STATE_BUF", buf, "64")
    if len != "0" {
        emit intToPtr(_guiBufToStr(buf, 64))
    }
    let heap = GetProcessHeap()
    let s = HeapAlloc(heap, "0", "4104")
    bufSetQwordAt(s, "0", "0")
    SetEnvironmentVariableA("KRK_STATE_BUF", ptrToInt(s))
    emit s
}
func _krkRawCopyStr(src) {
    let n = len(src)
    let heap = GetProcessHeap()
    let dst = HeapAlloc(heap, "0", (n + 1) + "")
    let i = 0
    while i < n {
        bufSetByte(dst, i + "", charCode(src[i]))
        i = i + 1
    }
    bufSetByte(dst, n + "", "0")
    emit dst
}
func guiStateSet(key, value) {
    let s = _krkStateBuf()
    let count = toInt(bufGetQwordAt(s, "0"))
    let i = 0
    while i < count {
        let off = 8 + i * 16
        let kStr = intToPtr(bufGetQwordAt(s, off + ""))
        if kStr == key {
            bufSetQwordAt(s, (off + 8) + "", ptrToInt(value))
            emit "1"
        }
        i = i + 1
    }
    if count >= 256 { emit "0" }
    let off = 8 + count * 16
    bufSetQwordAt(s, off + "", ptrToInt(_krkRawCopyStr(key)))
    bufSetQwordAt(s, (off + 8) + "", ptrToInt(value))
    bufSetQwordAt(s, "0", (count + 1) + "")
    emit "1"
}
func guiStateGet(key) {
    let s = _krkStateBuf()
    let count = toInt(bufGetQwordAt(s, "0"))
    let i = 0
    while i < count {
        let off = 8 + i * 16
        let kStr = intToPtr(bufGetQwordAt(s, off + ""))
        if kStr == key {
            emit intToPtr(bufGetQwordAt(s, (off + 8) + ""))
        }
        i = i + 1
    }
    emit ""
}

// Periodic-timer helpers. `cb` must be a 0-arg Krypton function
// passed via funcptr(). Returns a timer-id string (use to kill).
// 2026-05-11 Phase D: SetTimer on main hwnd with auto-allocated id;
// callback stored in cb.timer.<tid> for _krkWndProc to dispatch on WM_TIMER.
func guiSetTimer(ms, cb) {
    let main = guiStateGet("main.hwnd")
    if main == "" { emit "0" }
    let tid = guiStateGet("__krk_next_tid")
    let n = 1
    if tid != "" { n = toInt(tid) }
    guiStateSet("__krk_next_tid", (n + 1) + "")
    guiStateSet("cb.timer." + n, cb)
    SetTimer(main, n + "", ms + "", "0")
    emit n + ""
}
// 2026-05-11 Phase B: KillTimer direct. cfunc krGuiKillTimer also
// cleared its g_timer_cb[id] slot; we leak that slot until the program
// exits. With 16 slots this is fine for typical apps; full port lands
// when the timer-callback table moves out of cfunc.
func guiKillTimer(tid) {
    let main = guiStateGet("main.hwnd")
    if main == "" { emit "" }
    KillTimer(main, tid + "")
    emit ""
}

// Force dark mode for the main window via DWM immersive dark + the
// uxtheme DarkMode_Explorer subclass. 2026-05-11 Phase B port —
// pure Krypton, no cfunc / no LoadLibrary / no ordinal-135 hack.
// Scope is now the main hwnd only; child widgets need to be ported
// individually (the cfunc's EnumChildWindows + SetWindowTheme loop
// returns when WindowProc / widget creation moves out of cfunc).
//   DWMWA_USE_IMMERSIVE_DARK_MODE = 20 ; value = 4-byte BOOL.
func guiEnableDarkMode() {
    let hwnd = guiStateGet("main.hwnd")
    if hwnd == "" { emit "0" }
    let buf = bufNew(4)
    bufSetDwordAt(buf, "0", "1")
    DwmSetWindowAttribute(hwnd, "20", buf, "4")
    SetWindowTheme(hwnd, "DarkMode_Explorer", "0")
    emit "1"
}

// Replace the UI font (Segoe UI 10pt by default) with the caller's
// choice and propagate it to every existing child window.
// 2026-05-11 Phase D: pure-Krypton. Create HFONT via LOGFONTA + CreateFontIndirectA,
// then broadcast WM_SETFONT=48 to main window AND every direct child via
// GetWindow(hwnd, GW_CHILD=5) → GetWindow(prev, GW_HWNDNEXT=2) chain.
// Caches the HFONT in state for future widget creators to read.
func guiSetUiFont(family, ptSize) {
    let lf = bufNew("60")
    let neg = 0 - toInt(ptSize)
    bufSetDwordAt(lf, "0", neg + "")
    bufSetDwordAt(lf, "16", "400")
    bufSetByte(lf, "23", "1")
    bufSetByte(lf, "26", "5")
    let i = 0
    while i < len(family) {
        if i < 31 { bufSetByte(lf, 28 + i, charCode(family[i])) }
        i = i + 1
    }
    let hf = CreateFontIndirectA(lf)
    guiStateSet("ui.font.handle", hf)
    let main = guiStateGet("main.hwnd")
    if main == "" { emit "1" }
    SendMessageA(main, "48", hf, "1")
    let child = GetWindow(main, "5")
    while child != "0" {
        SendMessageA(child, "48", hf, "1")
        child = GetWindow(child, "2")
    }
    emit "1"
}

// Direct color overrides — for when the OS-level dark mode flip
// can't be relied on (older Win10, OS in light mode globally).
// SetWindowBg paints behind the whole window via WM_ERASEBKGND;
// SetUiTextColor controls the text color used in WM_CTLCOLORSTATIC
// fall-throughs; TreeSetColors directly sets a TreeView's bg/fg.
// 2026-05-11 Phase D: pure-Krypton. State keys read by _krkWndProc:
//   ui.window.bg     — hex string of current window-bg color
//   ui.window.brush  — cached HBRUSH (decimal) returned from WM_CTLCOLOR*
//   ui.text.color    — hex string of text color
// guiSetWindowBg also calls SetClassLongPtrA to swap the class brush so
// WM_ERASEBKGND fills with our color (no need for a custom WM_ERASEBKGND
// handler). GCLP_HBRBACKGROUND = -10.
func guiSetWindowBg(hexColor) {
    let color = _guiColorRefFromHex(hexColor)
    let brush = CreateSolidBrush(color + "")
    guiStateSet("ui.window.bg", hexColor)
    guiStateSet("ui.window.brush", brush)
    let main = guiStateGet("main.hwnd")
    if main != "" {
        SetClassLongPtrA(main, "-10", brush)
        InvalidateRect(main, "0", "1")
    }
    emit "1"
}
func guiSetUiTextColor(hexColor) {
    guiStateSet("ui.text.color", hexColor)
    let main = guiStateGet("main.hwnd")
    if main != "" {
        InvalidateRect(main, "0", "1")
    }
    emit "1"
}
// TVM_SETBKCOLOR=4381 (TV_FIRST+29), TVM_SETTEXTCOLOR=4382 (TV_FIRST+30).
// lParam = COLORREF (use -1 to reset to default).
func guiTreeSetColors(tree, bgHex, fgHex) {
    let h = _guiResolveHwnd(tree)
    if h == "0" { emit "0" }
    let bg = _guiColorRefFromHex(bgHex)
    let fg = _guiColorRefFromHex(fgHex)
    SendMessageA(h, "4381", "0", bg + "")
    SendMessageA(h, "4382", "0", fg + "")
    emit "1"
}
// 2026-05-11 Phase D: stash the color. NM_CUSTOMDRAW handling in WM_NOTIFY
// is TODO — without it, the status bar uses the system text color, but the
// cfunc dependency is eliminated.
func guiStatusTextColor(bar, hexColor) {
    let h = _guiResolveHwnd(bar)
    guiStateSet("status.text." + h, hexColor)
    emit ""
}

// Line-number gutter — a small column to the left of a RichEdit
// that paints 1-based numbers for every visible line. The bound
// RichEdit handle is the control whose lines we count. After text
// changes or scrolls, call guiLineNumberRefresh(gutter) so the
// numbers redraw.
// 2026-05-11 Phase D: pure-Krypton STATIC control. Custom WM_PAINT
// to render 1-based line numbers is TODO (needs DrawText + line-count
// from the bound RichEdit) — until then, the gutter is a blank column
// but no cfunc dependency.
func guiLineNumberArea(parent, x, y, w, h, rich) {
    let pHwnd = _guiHexToInt(parent)
    let hInst = GetModuleHandleA("0")
    let id = _guiNextId()
    let ctl = CreateWindowExA("0", "STATIC", "", "1342177280", x + "", y + "", w + "", h + "", pHwnd + "", id, hInst, "0")
    if ctl == "0" { emit "0" }
    guiStateSet("linenum.rich." + id, rich)
    emit id
}
// 2026-05-11 Phase D: simple invalidate+update. The actual line-number
// rendering needs WM_PAINT custom drawing in `_krkWndProc` (TODO).
// As-is, this triggers a repaint but the gutter remains blank.
func guiLineNumberRefresh(gutter) {
    let h = _guiResolveHwnd(gutter)
    if h == "0" { emit "" }
    InvalidateRect(h, "0", "1")
    UpdateWindow(h)
    emit ""
}
// 2026-05-11 Phase D: stash the color in state. Owner-draw via WM_DRAWITEM
// in `_krkWndProc` is TODO — without it, the active-tab still renders with
// the default theme color, but the cfunc dependency is eliminated.
func guiTabsSetActiveBg(tabs, hexColor) {
    let h = _guiResolveHwnd(tabs)
    guiStateSet("tabs.bg." + h, hexColor)
    emit ""
}
