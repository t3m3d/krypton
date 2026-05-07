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
// Uses the C codegen path because Krypton's native pipeline doesn't
// yet support arbitrary cross-language callbacks (Win32 WindowProc /
// Cocoa target-action). Every API below is implemented in cfunc { }
// and exposed as a thin Krypton wrapper. Drop-in replaceable when
// native callbacks land.
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


jxt {
    func krGuiInit()
    func krGuiWindow(title, w, h)             -> char_ptr
    func krGuiShow(hwnd)
    func krGuiButton(parent, label, x, y, w, h) -> char_ptr
    func krGuiLabel(parent, text, x, y, w, h)  -> char_ptr
    func krGuiTextInput(parent, x, y, w, h)    -> char_ptr
    func krGuiTextArea(parent, x, y, w, h)     -> char_ptr
    func krGuiRichEdit(parent, x, y, w, h)     -> char_ptr
    func krGuiRichSetFmt(rich, start, end, hexColor, bold)
    func krGuiRichClearFmt(rich)
    func krGuiRichAppend(rich, text, hexColor, bold)
    func krGuiRichReadOnly(rich, on)
    func krGuiRichSetMonoFont(rich, family, ptSize)
    func krGuiCheckbox(parent, label, x, y, w, h) -> char_ptr
    func krGuiIsChecked(hwnd)                  -> char_ptr
    func krGuiSetChecked(hwnd, on)
    func krGuiListbox(parent, x, y, w, h)      -> char_ptr
    func krGuiListAdd(hwnd, item)
    func krGuiListClear(hwnd)
    func krGuiListSelected(hwnd)               -> char_ptr
    func krGuiProgress(parent, x, y, w, h)     -> char_ptr
    func krGuiProgressSet(hwnd, percent)
    func krGuiTreeView(parent, x, y, w, h)     -> char_ptr
    func krGuiTreeAdd(tree, parent_item, label) -> char_ptr
    func krGuiTreeClear(tree)
    func krGuiTreeSelected(tree)               -> char_ptr
    func krGuiTabs(parent, x, y, w, h)         -> char_ptr
    func krGuiTabAdd(tabs, label)              -> char_ptr
    func krGuiTabSelected(tabs)                -> char_ptr
    func krGuiOnChange(hwnd, sinkPtr)
    func krGuiMenuBegin(window)                -> char_ptr
    func krGuiMenu(menubar, label)             -> char_ptr
    func krGuiMenuItem(popup, label)           -> char_ptr
    func krGuiMenuSeparator(popup)
    func krGuiMenuAdd(menu, label)             -> char_ptr
    func krGuiStatusBar(window)                -> char_ptr
    func krGuiStatusParts(bar, widthsCsv)
    func krGuiStatusSet(bar, idx, text)
    func krGuiStatusGet(bar, idx)              -> char_ptr
    func krGuiStatusIcon(bar, idx, iconName)
    func krGuiStatusBgColor(bar, hex)
    func krGuiMove(handle, x, y, w, h)
    func krGuiDock(window)                     -> char_ptr
    func krGuiDockTop(dock, hwnd, size)
    func krGuiDockBottom(dock, hwnd, size)
    func krGuiDockLeft(dock, hwnd, size)
    func krGuiDockRight(dock, hwnd, size)
    func krGuiDockFill(dock, hwnd)
    func krGuiDockApply(dock)
    func krGuiSplitter(parent, x, y, w, h, orientation) -> char_ptr
    func krGuiSplitterPos(splitter)            -> char_ptr
    func krGuiCombo(parent, x, y, w, h)        -> char_ptr
    func krGuiComboAdd(combo, item)
    func krGuiComboClear(combo)
    func krGuiComboSelected(combo)             -> char_ptr
    func krGuiComboSet(combo, idx)
    func krGuiColorPicker(initialHex)          -> char_ptr
    func krGuiDatePicker(parent, x, y, w, h)   -> char_ptr
    func krGuiDateGet(picker)                  -> char_ptr
    func krGuiDateSet(picker, ymd)
    func krGuiScrollbar(parent, x, y, w, h, vertical) -> char_ptr
    func krGuiScrollbarRange(sb, lo, hi, page)
    func krGuiScrollbarValue(sb)               -> char_ptr
    func krGuiScrollbarSet(sb, value)
    func krGuiVStack(parent, x, y, w, gap)     -> char_ptr
    func krGuiHStack(parent, x, y, h, gap)     -> char_ptr
    func krGuiVNext(stack, height)             -> char_ptr
    func krGuiHNext(stack, width)              -> char_ptr
    func krGuiStackParent(stack)               -> char_ptr
    func krGuiStackX(stack)                    -> char_ptr
    func krGuiStackY(stack)                    -> char_ptr
    func krGuiStackW(stack)                    -> char_ptr
    func krGuiStackH(stack)                    -> char_ptr
    func krGuiStackGap(stack)                  -> char_ptr
    func krGuiStackGapAdd(stack, pixels)
    func krGuiImage(parent, path, x, y, w, h)  -> char_ptr
    func krGuiImageSet(image, path)
    func krGuiSlider(parent, x, y, w, h)       -> char_ptr
    func krGuiSliderRange(slider, lo, hi)
    func krGuiSliderSet(slider, value)
    func krGuiSliderValue(slider)              -> char_ptr
    func krGuiSpinbox(parent, x, y, w, h)      -> char_ptr
    func krGuiSpinboxRange(spin, lo, hi)
    func krGuiSpinboxSet(spin, value)
    func krGuiSpinboxValue(spin)               -> char_ptr
    func krGuiToolbar(window)                  -> char_ptr
    func krGuiToolButton(toolbar, label, iconName) -> char_ptr
    func krGuiToolSep(toolbar)
    func krGuiToolbarHeight(toolbar)           -> char_ptr
    func krGuiOpenFile(title, filterCsv)       -> char_ptr
    func krGuiSaveFile(title, filterCsv, defaultName) -> char_ptr
    func krGuiPickFolder(title)                -> char_ptr
    func krGuiSetText(hwnd, text)
    func krGuiGetText(hwnd)                    -> char_ptr
    func krGuiOnClick(hwnd, sinkPtr)
    func krGuiMessageBox(title, msg)
    func krGuiRun()
    func krGuiQuit()
}


cfunc {
#if defined(_WIN32)
    // Pull in modern API surface (SetWindowTheme, IsThemeActive, etc.)
    // before windows.h locks the version.
    #ifndef _WIN32_WINNT
    #define _WIN32_WINNT 0x0601    /* Windows 7 baseline */
    #endif
    #ifndef WINVER
    #define WINVER       0x0601
    #endif

    #include <windows.h>
    #include <commctrl.h>
    #include <commdlg.h>
    #include <shlobj.h>
    #include <uxtheme.h>
    #include <stdio.h>
    #include <string.h>
    #include <stdlib.h>

    // The DwmSetWindowAttribute path needs a recent SDK; declare the
    // attribute id manually for portability.
    #ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
    #define DWMWA_USE_IMMERSIVE_DARK_MODE 20
    #endif
    /* TreeView extended styles — missing from older mingw headers. */
    #ifndef TVS_EX_DOUBLEBUFFER
    #define TVS_EX_DOUBLEBUFFER       0x0004
    #endif
    #ifndef TVS_EX_FADEINOUTEXPANDOS
    #define TVS_EX_FADEINOUTEXPANDOS  0x0040
    #endif
    #ifndef TVM_SETEXTENDEDSTYLE
    #define TVM_SETEXTENDEDSTYLE      (TV_FIRST + 44)
    #endif
    #ifndef DWMWA_BORDER_COLOR
    #define DWMWA_BORDER_COLOR 34
    #endif
    #ifndef DWMWA_CAPTION_COLOR
    #define DWMWA_CAPTION_COLOR 35
    #endif

    typedef char* (*kr_gui_cb)(void);

    // Map control-id → registered Krypton callback. Sized for tens of
    // controls per app; bump if a single program needs more.
    //   g_cb        — WM_COMMAND clicks (buttons, menu items, checkboxes)
    //   g_change_cb — WM_NOTIFY change events (tree selection, tab change)
    #define KR_GUI_MAX_CB 256
    static kr_gui_cb g_cb[KR_GUI_MAX_CB];
    static kr_gui_cb g_change_cb[KR_GUI_MAX_CB];
    static int g_next_id = 1000;          // start above standard control ids

    static const wchar_t* g_class_name = L"KryptonGuiWnd";
    static int   g_inited = 0;
    static HWND  g_main_hwnd = NULL;
    static HWND  g_status_bar = NULL;     // tracked so WM_SIZE can resize it
    static HWND  g_toolbar    = NULL;     // tracked so WM_SIZE auto-sizes it
    static HFONT g_ui_font   = NULL;     // Segoe UI 10pt — applied to every control
    static int   g_dark      = 0;        // toggled in krGuiWindow per OS theme

    // Forward decls — defined later but called from kr_gui_proc on WM_SIZE.
    static void kr_gui_apply_parts(void);
    static void kr_gui_reflow_all(int new_client_w, int new_client_h);
    static void kr_gui_docks_relayout_for(HWND wnd);

    // Multi-monitor scan: find the first non-primary monitor. Used by
    // krGuiWindow to place popups on the secondary screen so they
    // never land on top of whatever's running fullscreen on the
    // primary (typical multi-monitor work flow: game / video on
    // primary, productivity tools on secondary).
    struct kr_gui_mon_scan { HMONITOR primary; HMONITOR secondary; };
    static BOOL CALLBACK kr_gui_enum_mon(HMONITOR h, HDC dc, LPRECT r, LPARAM lp) {
        (void)dc; (void)r;
        struct kr_gui_mon_scan* s = (struct kr_gui_mon_scan*)lp;
        MONITORINFO mi;
        mi.cbSize = sizeof(mi);
        if (!GetMonitorInfoW(h, &mi)) return TRUE;
        if (mi.dwFlags & MONITORINFOF_PRIMARY) {
            if (!s->primary) s->primary = h;
        } else {
            if (!s->secondary) s->secondary = h;
        }
        return TRUE;
    }

    // Forward — apply our UI font to a freshly-created control.
    static void kr_gui_skin(HWND ctl) {
        if (!ctl) return;
        if (g_ui_font) SendMessageW(ctl, WM_SETFONT, (WPARAM)g_ui_font, MAKELPARAM(TRUE, 0));
    }

    // Per-call duplicated buffer — used everywhere we return a
    // string handle so callers' Krypton variables don't all alias one
    // static buffer that gets clobbered by subsequent calls. Tiny
    // process-lifetime leak (~30 bytes per widget) but the right
    // semantics — handles are immutable identifiers.
    static char* kr_gui_dup(const char* s) {
        size_t n = strlen(s) + 1;
        char* p = (char*)malloc(n);
        if (p) memcpy(p, s, n);
        return p;
    }

    // ── UTF-8 ↔ UTF-16 conversion ─────────────────────────────
    //
    // Krypton strings are UTF-8 (kcc reads .k files as raw bytes;
    // source-level text is UTF-8). Every W-suffix Win32 API takes
    // wchar_t* (UTF-16 on Windows). These helpers convert at the
    // boundary. Both leak per call (process-lifetime malloc) — fine
    // since we're not in a tight loop.

    static wchar_t* kr_gui_to_w(const char* s) {
        if (!s) s = "";
        int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
        if (n <= 0) {
            wchar_t* p = (wchar_t*)malloc(sizeof(wchar_t));
            if (p) p[0] = 0;
            return p;
        }
        wchar_t* w = (wchar_t*)malloc(sizeof(wchar_t) * n);
        if (!w) return NULL;
        MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
        return w;
    }

    static char* kr_gui_to_u(const wchar_t* w) {
        if (!w) w = L"";
        int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
        if (n <= 0) {
            char* p = (char*)malloc(1);
            if (p) p[0] = 0;
            return p;
        }
        char* u = (char*)malloc(n);
        if (!u) return NULL;
        WideCharToMultiByte(CP_UTF8, 0, w, -1, u, n, NULL, NULL);
        return u;
    }

    // Read AppsUseLightTheme from registry → 1 if dark, 0 if light.
    static int kr_gui_os_dark(void) {
        HKEY k;
        if (RegOpenKeyExA(HKEY_CURRENT_USER,
                          "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                          0, KEY_READ, &k) != ERROR_SUCCESS) return 1;
        DWORD v = 1, sz = sizeof(v);
        RegQueryValueExA(k, "AppsUseLightTheme", NULL, NULL, (LPBYTE)&v, &sz);
        RegCloseKey(k);
        return v == 0 ? 1 : 0;
    }

    static int kr_gui_register_id(void) {
        int id = g_next_id++;
        if (id - 1000 < KR_GUI_MAX_CB) g_cb[id - 1000] = NULL;
        return id;
    }

    static LRESULT CALLBACK kr_gui_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        if (msg == WM_SIZE) {
            // Forward resize to chrome bars so they span their edges
            // automatically. Status bar reapplies its part-widths spec
            // so proportional cells scale; toolbar auto-sizes itself.
            if (g_toolbar) {
                SendMessageW(g_toolbar, TB_AUTOSIZE, 0, 0);
            }
            if (g_status_bar) {
                SendMessageW(g_status_bar, WM_SIZE, 0, 0);
                kr_gui_apply_parts();
            }
            // Reflow elastic V-stacks so any widget that filled the
            // stack's full width grows / shrinks with the window.
            int cw = LOWORD(lp);
            int ch = HIWORD(lp);
            kr_gui_reflow_all(cw, ch);
            // Re-layout any dock manager attached to this window.
            kr_gui_docks_relayout_for(hwnd);
        }
        if (msg == WM_COMMAND) {
            int id = (int)LOWORD(wp);
            int slot = id - 1000;
            if (slot >= 0 && slot < KR_GUI_MAX_CB && g_cb[slot]) {
                g_cb[slot]();
                return 0;
            }
        }
        if (msg == WM_HSCROLL || msg == WM_VSCROLL) {
            // Sliders / trackbars send WM_xSCROLL to the parent on drag.
            // The control HWND is in lParam — look up its registered
            // change callback via the dialog-id lookup.
            HWND ctl = (HWND)lp;
            if (ctl) {
                int id = GetDlgCtrlID(ctl);
                int slot = id - 1000;
                if (slot >= 0 && slot < KR_GUI_MAX_CB && g_change_cb[slot]) {
                    g_change_cb[slot]();
                    return 0;
                }
            }
        }
        if (msg == WM_NOTIFY) {
            NMHDR* nm = (NMHDR*)lp;
            int id = (int)nm->idFrom;
            int slot = id - 1000;
            // Selection-changed events from Tree (TVN_SELCHANGEDW) and
            // Tabs (TCN_SELCHANGE). We use the W variant of the tree
            // notification since the control was registered Wide.
            if (slot >= 0 && slot < KR_GUI_MAX_CB && g_change_cb[slot]) {
                if (nm->code == TVN_SELCHANGEDW ||
                    nm->code == TCN_SELCHANGE) {
                    g_change_cb[slot]();
                    return 0;
                }
            }
        }
        return DefWindowProcW(hwnd, msg, wp, lp);
    }

    static void kr_gui_register_class(HINSTANCE hInst) {
        static int registered = 0;
        if (registered) return;
        WNDCLASSEXW wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = kr_gui_proc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorW(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExW(&wc);
        registered = 1;
    }

    // Activate Common Controls v6 for themed buttons/edits/etc. without
    // needing a build-time .manifest. We write the side-by-side manifest
    // to a temp file and feed it to CreateActCtxA at runtime. This is
    // what makes buttons rounded + edit fields modern instead of the
    // 1995-era classic theme.
    static int kr_gui_enable_themes(void) {
        static const char* manifest =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            "<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">\n"
            "  <dependency><dependentAssembly>\n"
            "    <assemblyIdentity type=\"win32\" name=\"Microsoft.Windows.Common-Controls\"\n"
            "      version=\"6.0.0.0\" processorArchitecture=\"*\"\n"
            "      publicKeyToken=\"6595b64144ccf1df\" language=\"*\" />\n"
            "  </dependentAssembly></dependency>\n"
            "</assembly>\n";

        char tmpDir[MAX_PATH], tmpFile[MAX_PATH];
        if (!GetTempPathA(MAX_PATH, tmpDir)) return 0;
        snprintf(tmpFile, sizeof(tmpFile), "%skr_gui_%lu.manifest",
                 tmpDir, (unsigned long)GetCurrentProcessId());

        FILE* f = fopen(tmpFile, "wb");
        if (!f) return 0;
        fputs(manifest, f);
        fclose(f);

        ACTCTXA actCtx;
        memset(&actCtx, 0, sizeof(actCtx));
        actCtx.cbSize   = sizeof(actCtx);
        actCtx.lpSource = tmpFile;
        HANDLE h = CreateActCtxA(&actCtx);
        if (h == INVALID_HANDLE_VALUE) return 0;
        ULONG_PTR cookie = 0;
        ActivateActCtx(h, &cookie);
        // Intentionally leak h + cookie — process-lifetime activation.
        return 1;
    }

    char* krGuiInit(void) {
        if (g_inited) return (char*)"1";
        for (int i = 0; i < KR_GUI_MAX_CB; i++) g_cb[i] = NULL;
        for (int i = 0; i < KR_GUI_MAX_CB; i++) g_change_cb[i] = NULL;

        // Themes BEFORE InitCommonControls so v6 classes register.
        kr_gui_enable_themes();
        INITCOMMONCONTROLSEX icc;
        icc.dwSize = sizeof(icc);
        icc.dwICC  = ICC_STANDARD_CLASSES | ICC_WIN95_CLASSES |
                     ICC_TREEVIEW_CLASSES | ICC_TAB_CLASSES |
                     ICC_PROGRESS_CLASS   | ICC_BAR_CLASSES |
                     ICC_UPDOWN_CLASS     | ICC_DATE_CLASSES;
        InitCommonControlsEx(&icc);

        // Default UI font — Segoe UI 10pt is what Win10/11 system uses.
        // CreateFontA(height_negative_pt × dpi/72, ...). 10pt at 96 DPI
        // ≈ -13. Modern Win11 apps tend to use 11pt-ish.
        g_ui_font = CreateFontA(
            -13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");

        g_dark = kr_gui_os_dark();

        kr_gui_register_class(GetModuleHandleA(NULL));
        g_inited = 1;
        return (char*)"1";
    }

    char* krGuiWindow(char* title, char* w, char* h) {
        if (!g_inited) krGuiInit();
        int width  = atoi(w ? w : "400");
        int height = atoi(h ? h : "300");
        HINSTANCE hInst = GetModuleHandleA(NULL);

        // Place the window on the secondary monitor when one exists
        // so popups never land on top of fullscreen apps running on
        // the primary. Single-monitor systems fall back to primary.
        int x = CW_USEDEFAULT, y = CW_USEDEFAULT;
        struct kr_gui_mon_scan scan = { NULL, NULL };
        EnumDisplayMonitors(NULL, NULL, kr_gui_enum_mon, (LPARAM)&scan);
        HMONITOR target_mon = scan.secondary ? scan.secondary : scan.primary;
        if (target_mon) {
            MONITORINFO mi;
            mi.cbSize = sizeof(mi);
            if (GetMonitorInfoW(target_mon, &mi)) {
                int mw = mi.rcWork.right  - mi.rcWork.left;
                int mh = mi.rcWork.bottom - mi.rcWork.top;
                x = mi.rcWork.left + (mw - width)  / 2;
                y = mi.rcWork.top  + (mh - height) / 2;
            }
        }

        wchar_t* wtitle = kr_gui_to_w(title ? title : "Krypton");
        HWND hwnd = CreateWindowExW(
            0, g_class_name, wtitle,
            WS_OVERLAPPEDWINDOW,
            x, y, width, height,
            NULL, NULL, hInst, NULL);
        if (!hwnd) return (char*)"0";
        if (!g_main_hwnd) g_main_hwnd = hwnd;

        // Match OS dark mode if available. Fails silently on older
        // Windows versions where DWMWA_USE_IMMERSIVE_DARK_MODE is
        // unsupported.
        HMODULE dwm = LoadLibraryA("dwmapi.dll");
        if (dwm) {
            typedef HRESULT (WINAPI *DwmSetWindowAttr_t)(HWND, DWORD, LPCVOID, DWORD);
            DwmSetWindowAttr_t pSet = (DwmSetWindowAttr_t)GetProcAddress(dwm, "DwmSetWindowAttribute");
            if (pSet) {
                BOOL dark = TRUE;
                pSet(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
            }
        }

        // Encode the HWND as a hex pointer string so Krypton can hold
        // it as a normal string value and pass back later.
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)hwnd);
        return kr_gui_dup(buf);
    }

    char* krGuiShow(char* hwnd_str) {
        HWND hwnd = NULL;
        sscanf(hwnd_str, "%p", (void**)&hwnd);
        if (!hwnd) return (char*)"0";
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }

    static HWND kr_gui_create_child_w(const wchar_t* cls, const char* text, int style,
                                      char* parent_str, int x, int y, int w, int h, int id) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return NULL;
        HINSTANCE hInst = GetModuleHandleA(NULL);
        wchar_t* wtext = kr_gui_to_w(text ? text : "");
        HWND ctl = CreateWindowExW(
            0, cls, wtext,
            WS_CHILD | WS_VISIBLE | style,
            x, y, w, h,
            parent, (HMENU)(LONG_PTR)id, hInst, NULL);
        kr_gui_skin(ctl);
        return ctl;
    }

    char* krGuiButton(char* parent_str, char* label, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND ctl = kr_gui_create_child_w(L"BUTTON", label, BS_PUSHBUTTON,
                                         parent_str, atoi(xs), atoi(ys), atoi(ws), atoi(hs), id);
        if (!ctl) return (char*)"0";
        // Return id as a decimal string so guiOnClick can find it.
        // Ids start at 1000 and never overlap so can't be confused
        // with raw pointers.
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiLabel(char* parent_str, char* text, char* xs, char* ys, char* ws, char* hs) {
        HWND ctl = kr_gui_create_child_w(
            L"STATIC", text, SS_LEFT,
            parent_str, atoi(xs), atoi(ys), atoi(ws), atoi(hs), 0);
        if (!ctl) return (char*)"0";
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiTextInput(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        HWND ctl = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id,
            GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    // ── Multi-line text area ───────────────────────────────────
    char* krGuiTextArea(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        HWND ctl = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL |
            ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    // ── RichEdit (msftedit.dll RICHEDIT50W) ────────────────────
    //
    // Per-character formatting — what we need for code-editor-style
    // syntax highlighting. msftedit.dll registers RICHEDIT50W; we
    // dynamic-load on first use so no -lmsimg32 link tax.
    //
    //   guiRichEdit(parent, x, y, w, h)            → handle
    //   guiRichSetFmt(rich, start, end, hex, bold) → color a range
    //   guiRichClearFmt(rich)                       → reset all to plain
    //   guiRichAppend(rich, text, hex, bold)        → tail with color
    //   guiRichReadOnly(rich, on)                   → 1 to lock edits
    //   guiRichSetMonoFont(rich, "Consolas", 11)    → font for whole control

    static int g_richedit_loaded = 0;

    static int kr_rich_load(void) {
        if (g_richedit_loaded) return 1;
        if (!LoadLibraryA("msftedit.dll")) return 0;
        g_richedit_loaded = 1;
        return 1;
    }

    static COLORREF kr_parse_hex_color(const char* hex) {
        const char* p = hex ? hex : "";
        if (*p == '#') p++;
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
        unsigned int v = 0;
        sscanf(p, "%x", &v);
        return RGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    }

    char* krGuiRichEdit(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        if (!kr_rich_load()) return (char*)"0";
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        HWND ctl = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"RICHEDIT50W", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL |
            ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL |
            ES_NOHIDESEL | ES_WANTRETURN,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        // RichEdit doesn't honour the global Segoe UI font well — set
        // a sensible monospaced default so it looks like a code editor
        // out of the box.
        HFONT mono = CreateFontA(
            -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN, "Consolas");
        if (mono) SendMessageW(ctl, WM_SETFONT, (WPARAM)mono, MAKELPARAM(TRUE, 0));
        // Subscribe to all change/selection notifications so callers
        // can wire onChange if they want a "buffer dirty" signal.
        SendMessageW(ctl, EM_SETEVENTMASK, 0, ENM_CHANGE | ENM_SELCHANGE);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiRichSetFmt(char* h, char* s_str, char* e_str, char* hex, char* bold_str) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        int s = atoi(s_str ? s_str : "0");
        int e = atoi(e_str ? e_str : "0");
        int bold = atoi(bold_str ? bold_str : "0");
        // Save and restore the user's selection so format-runs from
        // syntax-highlight passes don't yank the cursor around.
        CHARRANGE saved;
        SendMessageW(ctl, EM_EXGETSEL, 0, (LPARAM)&saved);
        CHARRANGE cr; cr.cpMin = s; cr.cpMax = e;
        SendMessageW(ctl, EM_EXSETSEL, 0, (LPARAM)&cr);
        CHARFORMAT2W cf;
        memset(&cf, 0, sizeof(cf));
        cf.cbSize    = sizeof(cf);
        cf.dwMask    = CFM_COLOR | CFM_BOLD;
        cf.crTextColor = kr_parse_hex_color(hex);
        cf.dwEffects   = bold ? CFE_BOLD : 0;
        SendMessageW(ctl, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
        SendMessageW(ctl, EM_EXSETSEL, 0, (LPARAM)&saved);
        return (char*)"1";
    }

    char* krGuiRichClearFmt(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        CHARRANGE saved;
        SendMessageW(ctl, EM_EXGETSEL, 0, (LPARAM)&saved);
        CHARRANGE all; all.cpMin = 0; all.cpMax = -1;
        SendMessageW(ctl, EM_EXSETSEL, 0, (LPARAM)&all);
        CHARFORMAT2W cf;
        memset(&cf, 0, sizeof(cf));
        cf.cbSize  = sizeof(cf);
        cf.dwMask  = CFM_COLOR | CFM_BOLD | CFM_ITALIC | CFM_UNDERLINE;
        cf.crTextColor = RGB(0xd4, 0xd4, 0xd4);
        cf.dwEffects   = 0;
        SendMessageW(ctl, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
        SendMessageW(ctl, EM_EXSETSEL, 0, (LPARAM)&saved);
        return (char*)"1";
    }

    char* krGuiRichAppend(char* h, char* text, char* hex, char* bold_str) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        // Snap selection to end-of-text, set format, insert.
        int len_chars = (int)SendMessageW(ctl, WM_GETTEXTLENGTH, 0, 0);
        CHARRANGE end; end.cpMin = len_chars; end.cpMax = len_chars;
        SendMessageW(ctl, EM_EXSETSEL, 0, (LPARAM)&end);
        CHARFORMAT2W cf;
        memset(&cf, 0, sizeof(cf));
        cf.cbSize = sizeof(cf);
        cf.dwMask = CFM_COLOR | CFM_BOLD;
        cf.crTextColor = kr_parse_hex_color(hex);
        cf.dwEffects   = atoi(bold_str ? bold_str : "0") ? CFE_BOLD : 0;
        SendMessageW(ctl, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
        wchar_t* w = kr_gui_to_w(text ? text : "");
        SendMessageW(ctl, EM_REPLACESEL, FALSE, (LPARAM)w);
        return (char*)"1";
    }

    char* krGuiRichReadOnly(char* h, char* on_str) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, EM_SETREADONLY,
                     atoi(on_str ? on_str : "0") ? TRUE : FALSE, 0);
        return (char*)"1";
    }

    char* krGuiRichSetMonoFont(char* h, char* family, char* pt_str) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        int pt = atoi(pt_str ? pt_str : "11");
        HFONT mono = CreateFontA(
            -(pt * 96 / 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN,
            (family && *family) ? family : "Consolas");
        if (mono) SendMessageW(ctl, WM_SETFONT, (WPARAM)mono, MAKELPARAM(TRUE, 0));
        return (char*)"1";
    }

    // ── Checkbox ───────────────────────────────────────────────
    char* krGuiCheckbox(char* parent_str, char* label, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND ctl = kr_gui_create_child_w(
            L"BUTTON", label, BS_AUTOCHECKBOX,
            parent_str, atoi(xs), atoi(ys), atoi(ws), atoi(hs), id);
        if (!ctl) return (char*)"0";
        // Reuse ID-based handle so onClick wiring works the same way.
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    static HWND kr_gui_resolve(char* s) {
        if (!s) return NULL;
        if (s[0] == '0' && s[1] == 'x') {
            HWND h = NULL;
            sscanf(s, "0x%llx", (unsigned long long*)&h);
            return h;
        }
        // Decimal control id — look up via parent dialog item.
        int id = atoi(s);
        if (id >= 1000 && g_main_hwnd) return GetDlgItem(g_main_hwnd, id);
        return NULL;
    }

    char* krGuiIsChecked(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        LRESULT r = SendMessageW(ctl, BM_GETCHECK, 0, 0);
        return r == BST_CHECKED ? (char*)"1" : (char*)"0";
    }

    char* krGuiSetChecked(char* h, char* on) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, BM_SETCHECK,
                     (atoi(on ? on : "0") ? BST_CHECKED : BST_UNCHECKED), 0);
        return (char*)"1";
    }

    // ── Listbox ────────────────────────────────────────────────
    char* krGuiListbox(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        HWND ctl = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"LISTBOX", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL |
            LBS_NOTIFY | LBS_HASSTRINGS,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiListAdd(char* h, char* item) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        wchar_t* w = kr_gui_to_w(item ? item : "");
        SendMessageW(ctl, LB_ADDSTRING, 0, (LPARAM)w);
        return (char*)"1";
    }

    char* krGuiListClear(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, LB_RESETCONTENT, 0, 0);
        return (char*)"1";
    }

    char* krGuiListSelected(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"";
        int idx = (int)SendMessageW(ctl, LB_GETCURSEL, 0, 0);
        if (idx < 0) return (char*)"";
        wchar_t buf[2048];
        SendMessageW(ctl, LB_GETTEXT, idx, (LPARAM)buf);
        return kr_gui_to_u(buf);
    }

    // ── Progress bar ───────────────────────────────────────────
    char* krGuiProgress(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        HWND ctl = CreateWindowExW(
            0, PROGRESS_CLASSW, NULL,
            WS_CHILD | WS_VISIBLE,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, NULL, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, PBM_SETRANGE, 0, MAKELPARAM(0, 100));
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiProgressSet(char* h, char* percent) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        int p = atoi(percent ? percent : "0");
        if (p < 0) p = 0;
        if (p > 100) p = 100;
        SendMessageW(ctl, PBM_SETPOS, p, 0);
        return (char*)"1";
    }

    // ── Tree view ──────────────────────────────────────────────
    char* krGuiTreeView(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        // TVS_HASBUTTONS forces expand markers; TVS_HASLINES +
        // TVS_LINESATROOT make the hierarchy obvious as a fallback if
        // Explorer theming doesn't apply. With Explorer theme the
        // lines disappear and you get clean triangle markers; without
        // it you fall back to classic [+]/[-] boxes with dotted lines.
        HWND ctl = CreateWindowExW(
            WS_EX_CLIENTEDGE, WC_TREEVIEWW, L"",
            WS_CHILD | WS_VISIBLE | TVS_HASBUTTONS | TVS_HASLINES |
            TVS_LINESATROOT | TVS_SHOWSELALWAYS,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        HMODULE uxtheme_mod = LoadLibraryA("uxtheme.dll");
        if (uxtheme_mod) {
            typedef HRESULT (WINAPI *SetWindowTheme_t)(HWND, LPCWSTR, LPCWSTR);
            SetWindowTheme_t pSet = (SetWindowTheme_t)
                GetProcAddress(uxtheme_mod, "SetWindowTheme");
            if (pSet) pSet(ctl, L"Explorer", NULL);
        }
        SendMessageW(ctl, TVM_SETEXTENDEDSTYLE,
                     TVS_EX_DOUBLEBUFFER | TVS_EX_FADEINOUTEXPANDOS,
                     TVS_EX_DOUBLEBUFFER | TVS_EX_FADEINOUTEXPANDOS);
        // Return as decimal id so onChange wiring works the same way
        // as buttons/menus.
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiTreeAdd(char* tree_str, char* parent_item_str, char* label) {
        HWND ctl = kr_gui_resolve(tree_str);
        if (!ctl) return (char*)"0";
        HTREEITEM parent_item = TVI_ROOT;
        if (parent_item_str && parent_item_str[0] == '0' && parent_item_str[1] == 'x') {
            sscanf(parent_item_str, "0x%llx", (unsigned long long*)&parent_item);
        }
        TVINSERTSTRUCTW ins;
        memset(&ins, 0, sizeof(ins));
        ins.hParent      = parent_item;
        ins.hInsertAfter = TVI_LAST;
        ins.item.mask    = TVIF_TEXT;
        ins.item.pszText = kr_gui_to_w(label ? label : "");
        HTREEITEM h = (HTREEITEM)SendMessageW(ctl, TVM_INSERTITEMW, 0, (LPARAM)&ins);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)h);
        return kr_gui_dup(buf);
    }

    char* krGuiTreeClear(char* tree_str) {
        HWND ctl = kr_gui_resolve(tree_str);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, TVM_DELETEITEM, 0, (LPARAM)TVI_ROOT);
        return (char*)"1";
    }

    char* krGuiTreeSelected(char* tree_str) {
        HWND ctl = kr_gui_resolve(tree_str);
        if (!ctl) return (char*)"";
        HTREEITEM sel = (HTREEITEM)SendMessageW(ctl, TVM_GETNEXTITEM, TVGN_CARET, 0);
        if (!sel) return (char*)"";
        wchar_t buf[1024];
        TVITEMW it;
        memset(&it, 0, sizeof(it));
        it.mask       = TVIF_TEXT | TVIF_HANDLE;
        it.hItem      = sel;
        it.pszText    = buf;
        it.cchTextMax = sizeof(buf) / sizeof(wchar_t);
        SendMessageW(ctl, TVM_GETITEMW, 0, (LPARAM)&it);
        return kr_gui_to_u(buf);
    }

    // ── Tab control ────────────────────────────────────────────
    // Just the strip — caller manages page contents (show/hide their
    // own widgets in the on-change callback).
    char* krGuiTabs(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        int id = kr_gui_register_id();
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        HWND ctl = CreateWindowExW(
            0, WC_TABCONTROLW, L"",
            WS_CHILD | WS_VISIBLE,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiTabAdd(char* tabs_str, char* label) {
        HWND ctl = kr_gui_resolve(tabs_str);
        if (!ctl) return (char*)"-1";
        TCITEMW it;
        memset(&it, 0, sizeof(it));
        it.mask    = TCIF_TEXT;
        it.pszText = kr_gui_to_w(label ? label : "");
        int idx = (int)SendMessageW(ctl, TCM_INSERTITEMW,
                                    SendMessageW(ctl, TCM_GETITEMCOUNT, 0, 0),
                                    (LPARAM)&it);
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", idx);
        return kr_gui_dup(buf);
    }

    char* krGuiTabSelected(char* tabs_str) {
        HWND ctl = kr_gui_resolve(tabs_str);
        if (!ctl) return (char*)"-1";
        int idx = (int)SendMessageW(ctl, TCM_GETCURSEL, 0, 0);
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", idx);
        return kr_gui_dup(buf);
    }

    char* krGuiOnChange(char* id_str, char* sinkPtr) {
        int id = atoi(id_str ? id_str : "0");
        int slot = id - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return (char*)"0";
        g_change_cb[slot] = (kr_gui_cb)sinkPtr;
        return (char*)"1";
    }

    // ── Menu bar ───────────────────────────────────────────────
    // Single top-level "menu" model: items added with krGuiMenuAdd
    // become flat buttons across the top of the window (File, Edit,
    // Help). Each click triggers the registered onClick callback for
    // its id, just like a button. Submenus are a follow-up.
    static HMENU g_menu = NULL;

    char* krGuiMenuBegin(char* window_str) {
        HWND parent = NULL;
        sscanf(window_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        if (!g_menu) g_menu = CreateMenu();
        SetMenu(parent, g_menu);
        DrawMenuBar(parent);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)g_menu);
        return kr_gui_dup(buf);
    }

    char* krGuiMenuAdd(char* menu_str, char* label) {
        // Legacy flat-item API. Kept for compat with old demos. New
        // code should use guiMenu + guiMenuItem for proper dropdowns.
        if (!g_menu) return (char*)"0";
        int id = kr_gui_register_id();
        wchar_t* w = kr_gui_to_w(label ? label : "");
        AppendMenuW(g_menu, MF_STRING, id, w);
        if (g_main_hwnd) DrawMenuBar(g_main_hwnd);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    // ── Dropdown menus (the standard model) ────────────────────
    //
    // guiMenu(menubar, "File") creates a dropdown attached to the
    // menubar and returns its handle. guiMenuItem(popup, "New") adds
    // a clickable item INSIDE the dropdown and returns an id to wire
    // with guiOnClick. guiMenuSeparator adds a visual divider.

    char* krGuiMenu(char* menubar_str, char* label) {
        if (!g_menu) return (char*)"0";
        HMENU pop = CreatePopupMenu();
        if (!pop) return (char*)"0";
        wchar_t* w = kr_gui_to_w(label ? label : "");
        AppendMenuW(g_menu, MF_POPUP, (UINT_PTR)pop, w);
        if (g_main_hwnd) DrawMenuBar(g_main_hwnd);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)pop);
        return kr_gui_dup(buf);
    }

    char* krGuiMenuItem(char* popup_str, char* label) {
        HMENU pop = NULL;
        if (popup_str && popup_str[0] == '0' && popup_str[1] == 'x') {
            sscanf(popup_str, "0x%llx", (unsigned long long*)&pop);
        }
        if (!pop) return (char*)"0";
        int id = kr_gui_register_id();
        wchar_t* w = kr_gui_to_w(label ? label : "");
        AppendMenuW(pop, MF_STRING, id, w);
        if (g_main_hwnd) DrawMenuBar(g_main_hwnd);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiMenuSeparator(char* popup_str) {
        HMENU pop = NULL;
        if (popup_str && popup_str[0] == '0' && popup_str[1] == 'x') {
            sscanf(popup_str, "0x%llx", (unsigned long long*)&pop);
        }
        if (!pop) return (char*)"0";
        AppendMenuW(pop, MF_SEPARATOR, 0, NULL);
        return (char*)"1";
    }

    // ── Dock layout (Visual Studio-ish) ────────────────────────
    //
    // A dock manager owns a set of child widgets, each tagged with a
    // side and a fixed size on its main axis. On every WM_SIZE of the
    // owning window the dock recomputes positions:
    //
    //   top    panels eat from the top edge
    //   bottom panels eat from the bottom edge
    //   left   panels eat from the left edge
    //   right  panels eat from the right edge
    //   fill   takes whatever's left in the middle (one of these)
    //
    // Insertion order matters — first dockTop is closer to the edge
    // than the second dockTop. The single fill widget always wins
    // the leftover middle box.
    //
    //   let dock = guiDock(win)
    //   guiDockTop(dock,    toolbar,   tbHeight)
    //   guiDockBottom(dock, statusbar, 28)
    //   guiDockLeft(dock,   tree,      240)
    //   guiDockFill(dock,   editor)
    //   guiDockApply(dock)         // initial layout

    typedef struct {
        HWND hwnd;
        int  side;        // 0=top, 1=bottom, 2=left, 3=right, 4=fill
        int  size;
    } kr_gui_dock_child;

    typedef struct {
        HWND window;
        kr_gui_dock_child kids[64];
        int  n_kids;
    } kr_gui_dock;

    #define KR_GUI_MAX_DOCKS 8
    static kr_gui_dock* g_docks[KR_GUI_MAX_DOCKS];
    static int g_n_docks = 0;

    static void kr_gui_dock_layout(kr_gui_dock* d) {
        if (!d || !d->window) return;
        RECT cr;
        GetClientRect(d->window, &cr);
        int top = cr.top, bot = cr.bottom, lft = cr.left, rgt = cr.right;
        // First pass: top / bottom / left / right consume edges in
        // declaration order. Fill is applied last with the leftover.
        for (int i = 0; i < d->n_kids; i++) {
            kr_gui_dock_child* c = &d->kids[i];
            if (!c->hwnd || c->side == 4) continue;
            int x, y, w, h;
            if (c->side == 0) {           // top
                x = lft; y = top; w = rgt - lft; h = c->size; top += c->size;
            } else if (c->side == 1) {    // bottom
                x = lft; y = bot - c->size; w = rgt - lft; h = c->size; bot -= c->size;
            } else if (c->side == 2) {    // left
                x = lft; y = top; w = c->size; h = bot - top; lft += c->size;
            } else {                      // right
                x = rgt - c->size; y = top; w = c->size; h = bot - top; rgt -= c->size;
            }
            SetWindowPos(c->hwnd, NULL, x, y, w, h,
                         SWP_NOZORDER | SWP_NOACTIVATE);
        }
        // Fill consumes whatever's left.
        for (int i = 0; i < d->n_kids; i++) {
            kr_gui_dock_child* c = &d->kids[i];
            if (c->side == 4 && c->hwnd) {
                SetWindowPos(c->hwnd, NULL, lft, top, rgt - lft, bot - top,
                             SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
    }

    static void kr_gui_docks_relayout_for(HWND wnd) {
        for (int i = 0; i < g_n_docks; i++) {
            if (g_docks[i] && g_docks[i]->window == wnd) {
                kr_gui_dock_layout(g_docks[i]);
            }
        }
    }

    char* krGuiDock(char* window_str) {
        HWND wnd = NULL;
        sscanf(window_str, "%p", (void**)&wnd);
        if (!wnd) return (char*)"0";
        kr_gui_dock* d = (kr_gui_dock*)calloc(1, sizeof(*d));
        if (!d) return (char*)"0";
        d->window = wnd;
        if (g_n_docks < KR_GUI_MAX_DOCKS) g_docks[g_n_docks++] = d;
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)d);
        return kr_gui_dup(buf);
    }

    static kr_gui_dock* kr_gui_dock_resolve(const char* h) {
        if (!h || h[0] != '0' || h[1] != 'x') return NULL;
        kr_gui_dock* d = NULL;
        sscanf(h, "0x%llx", (unsigned long long*)&d);
        return d;
    }

    static char* kr_gui_dock_add(char* dock_str, char* h_str, int side, int size) {
        kr_gui_dock* d = kr_gui_dock_resolve(dock_str);
        if (!d || d->n_kids >= 64) return (char*)"0";
        HWND ctl = kr_gui_resolve(h_str);
        if (!ctl) return (char*)"0";
        d->kids[d->n_kids].hwnd = ctl;
        d->kids[d->n_kids].side = side;
        d->kids[d->n_kids].size = size;
        d->n_kids++;
        return (char*)"1";
    }

    char* krGuiDockTop(char* d, char* h, char* s)    { return kr_gui_dock_add(d, h, 0, atoi(s)); }
    char* krGuiDockBottom(char* d, char* h, char* s) { return kr_gui_dock_add(d, h, 1, atoi(s)); }
    char* krGuiDockLeft(char* d, char* h, char* s)   { return kr_gui_dock_add(d, h, 2, atoi(s)); }
    char* krGuiDockRight(char* d, char* h, char* s)  { return kr_gui_dock_add(d, h, 3, atoi(s)); }
    char* krGuiDockFill(char* d, char* h)            { return kr_gui_dock_add(d, h, 4, 0); }
    char* krGuiDockApply(char* d_str) {
        kr_gui_dock* d = kr_gui_dock_resolve(d_str);
        if (d) kr_gui_dock_layout(d);
        return (char*)"1";
    }

    // ── Reposition any widget by handle ────────────────────────
    char* krGuiMove(char* h, char* xs, char* ys, char* ws, char* hs) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SetWindowPos(ctl, NULL, atoi(xs), atoi(ys), atoi(ws), atoi(hs),
                     SWP_NOZORDER | SWP_NOACTIVATE);
        return (char*)"1";
    }

    // ── Splitter (drag-to-resize bar) ──────────────────────────
    //
    //   guiSplitter(parent, x, y, w, h, "horizontal")
    //     A wide-thin bar — user drags up/down. Use to split a window
    //     into top + bottom panels.
    //   guiSplitter(parent, x, y, w, h, "vertical")
    //     A thin-tall bar — user drags left/right. Use to split into
    //     left + right panels.
    //
    //   guiOnChange(splitter, fn)   fires on drag — your callback
    //                               reads guiSplitterPos and moves
    //                               your panel widgets.
    //   guiSplitterPos(splitter)   current pixel position relative
    //                               to parent's client area.
    //
    // The splitter only moves itself; you reposition the panels in
    // your onChange callback. Splitter is a thin colored STATIC with
    // a custom WindowProc that handles mouse capture.

    typedef struct {
        HWND hwnd;
        int  orient;       // 0 = horizontal bar (drag y), 1 = vertical bar (drag x)
        int  dragging;
        POINT drag_start;  // mouse pos at WM_LBUTTONDOWN, in client coords
        int   pos;         // current top (h) or left (v) in parent client coords
    } kr_gui_splitter;

    #define KR_GUI_MAX_SPLITTERS 16
    static kr_gui_splitter g_splitters[KR_GUI_MAX_SPLITTERS];
    static int g_n_splitters = 0;

    static kr_gui_splitter* kr_gui_splitter_find(HWND h) {
        for (int i = 0; i < g_n_splitters; i++) {
            if (g_splitters[i].hwnd == h) return &g_splitters[i];
        }
        return NULL;
    }

    static LRESULT CALLBACK kr_gui_splitter_proc(HWND hwnd, UINT msg,
                                                 WPARAM wp, LPARAM lp,
                                                 UINT_PTR sub_id, DWORD_PTR data) {
        (void)sub_id; (void)data;
        kr_gui_splitter* sp = kr_gui_splitter_find(hwnd);
        if (!sp) return DefSubclassProc(hwnd, msg, wp, lp);

        if (msg == WM_LBUTTONDOWN) {
            SetCapture(hwnd);
            sp->dragging = 1;
            POINT pt = { (SHORT)LOWORD(lp), (SHORT)HIWORD(lp) };
            ClientToScreen(hwnd, &pt);
            ScreenToClient(GetParent(hwnd), &pt);
            sp->drag_start = pt;
            return 0;
        }
        if (msg == WM_LBUTTONUP) {
            sp->dragging = 0;
            ReleaseCapture();
            return 0;
        }
        if (msg == WM_MOUSEMOVE && sp->dragging) {
            POINT pt = { (SHORT)LOWORD(lp), (SHORT)HIWORD(lp) };
            ClientToScreen(hwnd, &pt);
            ScreenToClient(GetParent(hwnd), &pt);
            int dx = pt.x - sp->drag_start.x;
            int dy = pt.y - sp->drag_start.y;
            sp->drag_start = pt;

            RECT r;
            GetWindowRect(hwnd, &r);
            POINT origin = { r.left, r.top };
            ScreenToClient(GetParent(hwnd), &origin);
            int new_x = origin.x + (sp->orient == 1 ? dx : 0);
            int new_y = origin.y + (sp->orient == 0 ? dy : 0);
            SetWindowPos(hwnd, NULL, new_x, new_y, 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            sp->pos = (sp->orient == 0) ? new_y : new_x;

            // Fire onChange.
            int id = GetDlgCtrlID(hwnd);
            int slot = id - 1000;
            if (slot >= 0 && slot < KR_GUI_MAX_CB && g_change_cb[slot]) {
                g_change_cb[slot]();
            }
            return 0;
        }
        if (msg == WM_SETCURSOR) {
            SetCursor(LoadCursorW(NULL,
                sp->orient == 0 ? IDC_SIZENS : IDC_SIZEWE));
            return TRUE;
        }
        if (msg == WM_ERASEBKGND) {
            // Paint a 1-tone gray bar so it's visibly draggable.
            HDC dc = (HDC)wp;
            RECT r;
            GetClientRect(hwnd, &r);
            HBRUSH br = CreateSolidBrush(g_dark ? RGB(0x3a, 0x3a, 0x3a)
                                                : RGB(0xd0, 0xd0, 0xd0));
            FillRect(dc, &r, br);
            DeleteObject(br);
            return 1;
        }
        return DefSubclassProc(hwnd, msg, wp, lp);
    }

    char* krGuiSplitter(char* parent_str, char* xs, char* ys, char* ws, char* hs,
                        char* orient_str) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int orient = 0;       // default: horizontal bar
        if (orient_str && (orient_str[0] == 'v' || orient_str[0] == 'V')) orient = 1;

        int id = kr_gui_register_id();
        HWND ctl = CreateWindowExW(
            0, L"STATIC", L"",
            WS_CHILD | WS_VISIBLE | SS_NOTIFY | SS_OWNERDRAW,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";

        if (g_n_splitters < KR_GUI_MAX_SPLITTERS) {
            kr_gui_splitter* sp = &g_splitters[g_n_splitters++];
            sp->hwnd     = ctl;
            sp->orient   = orient;
            sp->dragging = 0;
            sp->pos      = (orient == 0) ? atoi(ys) : atoi(xs);
        }
        SetWindowSubclass(ctl, kr_gui_splitter_proc, 1, 0);

        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiSplitterPos(char* sp_str) {
        HWND ctl = kr_gui_resolve(sp_str);
        if (!ctl) return (char*)"0";
        kr_gui_splitter* sp = kr_gui_splitter_find(ctl);
        if (!sp) return (char*)"0";
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", sp->pos);
        return kr_gui_dup(buf);
    }

    // ── Combo box (dropdown list) ──────────────────────────────
    //
    //   guiCombo(parent, x, y, w, h)        → handle (dropdown list)
    //   guiComboAdd(combo, item)            → append item
    //   guiComboClear(combo)                → drop all items
    //   guiComboSelected(combo)             → text of selected item
    //   guiComboSet(combo, idx)             → set selection by index

    char* krGuiCombo(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        // CBS_DROPDOWNLIST = non-editable dropdown. Add CBS_DROPDOWN
        // for an editable variant.
        HWND ctl = CreateWindowExW(
            0, L"COMBOBOX", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL |
            CBS_DROPDOWNLIST | CBS_HASSTRINGS,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiComboAdd(char* h, char* item) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        wchar_t* w = kr_gui_to_w(item ? item : "");
        SendMessageW(ctl, CB_ADDSTRING, 0, (LPARAM)w);
        return (char*)"1";
    }

    char* krGuiComboClear(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, CB_RESETCONTENT, 0, 0);
        return (char*)"1";
    }

    char* krGuiComboSelected(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"";
        int idx = (int)SendMessageW(ctl, CB_GETCURSEL, 0, 0);
        if (idx < 0) return (char*)"";
        wchar_t buf[1024];
        SendMessageW(ctl, CB_GETLBTEXT, idx, (LPARAM)buf);
        return kr_gui_to_u(buf);
    }

    char* krGuiComboSet(char* h, char* idx_str) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, CB_SETCURSEL, atoi(idx_str ? idx_str : "0"), 0);
        return (char*)"1";
    }

    // ── Color picker (system ChooseColor dialog) ───────────────
    //
    //   guiColorPicker("0xff0000")  → "0xRRGGBB" or "" if cancelled
    //
    // Modal dialog. Use as: pop up, get string back, store in your
    // settings or apply via guiStatusBgColor / SetWindowText etc.

    char* krGuiColorPicker(char* initialHex) {
        // Parse initial color same as status bar tint.
        unsigned int v = 0;
        if (initialHex && *initialHex) {
            const char* p = initialHex;
            if (*p == '#') p++;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
            sscanf(p, "%x", &v);
        }
        COLORREF init = RGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);

        static COLORREF custom[16] = {0};
        CHOOSECOLORW cc;
        memset(&cc, 0, sizeof(cc));
        cc.lStructSize  = sizeof(cc);
        cc.hwndOwner    = g_main_hwnd;
        cc.rgbResult    = init;
        cc.lpCustColors = custom;
        cc.Flags        = CC_FULLOPEN | CC_RGBINIT | CC_ANYCOLOR;
        if (!ChooseColorW(&cc)) return (char*)"";
        char out[16];
        snprintf(out, sizeof(out), "0x%02X%02X%02X",
                 GetRValue(cc.rgbResult),
                 GetGValue(cc.rgbResult),
                 GetBValue(cc.rgbResult));
        return kr_gui_dup(out);
    }

    // ── Date picker (DateTimePicker) ───────────────────────────
    //
    //   guiDatePicker(parent, x, y, w, h)  → handle
    //   guiDateGet(picker)                 → "YYYY-MM-DD"
    //   guiDateSet(picker, "YYYY-MM-DD")
    //   guiOnChange(picker, fn)             → fires when user picks

    char* krGuiDatePicker(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        HWND ctl = CreateWindowExW(
            0, DATETIMEPICK_CLASSW, L"",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | DTS_SHORTDATEFORMAT,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiDateGet(char* h) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl) return (char*)"";
        SYSTEMTIME st;
        if (SendMessageW(ctl, DTM_GETSYSTEMTIME, 0, (LPARAM)&st) != GDT_VALID)
            return (char*)"";
        char out[16];
        snprintf(out, sizeof(out), "%04d-%02d-%02d",
                 st.wYear, st.wMonth, st.wDay);
        return kr_gui_dup(out);
    }

    char* krGuiDateSet(char* h, char* ymd) {
        HWND ctl = kr_gui_resolve(h);
        if (!ctl || !ymd) return (char*)"0";
        int y = 0, m = 0, d = 0;
        if (sscanf(ymd, "%d-%d-%d", &y, &m, &d) != 3) return (char*)"0";
        SYSTEMTIME st = {0};
        st.wYear  = (WORD)y;
        st.wMonth = (WORD)m;
        st.wDay   = (WORD)d;
        SendMessageW(ctl, DTM_SETSYSTEMTIME, GDT_VALID, (LPARAM)&st);
        return (char*)"1";
    }

    // ── Standalone scrollbar ────────────────────────────────────
    //
    //   guiScrollbar(parent, x, y, w, h, vertical)  → handle
    //   guiScrollbarRange(sb, lo, hi, page)
    //   guiScrollbarValue(sb)                       → current pos
    //   guiScrollbarSet(sb, value)
    //   guiOnChange(sb, fn)                         → drag fires

    char* krGuiScrollbar(char* parent_str, char* xs, char* ys, char* ws, char* hs, char* vert_str) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        int vert = atoi(vert_str ? vert_str : "0");
        HWND ctl = CreateWindowExW(
            0, L"SCROLLBAR", L"",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            (vert ? SBS_VERT : SBS_HORZ),
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiScrollbarRange(char* sb_str, char* lo_str, char* hi_str, char* page_str) {
        HWND ctl = kr_gui_resolve(sb_str);
        if (!ctl) return (char*)"0";
        SCROLLINFO si;
        memset(&si, 0, sizeof(si));
        si.cbSize = sizeof(si);
        si.fMask  = SIF_RANGE | SIF_PAGE;
        si.nMin   = atoi(lo_str   ? lo_str   : "0");
        si.nMax   = atoi(hi_str   ? hi_str   : "100");
        si.nPage  = (UINT)atoi(page_str ? page_str : "10");
        SetScrollInfo(ctl, SB_CTL, &si, TRUE);
        return (char*)"1";
    }

    char* krGuiScrollbarValue(char* sb_str) {
        HWND ctl = kr_gui_resolve(sb_str);
        if (!ctl) return (char*)"0";
        SCROLLINFO si;
        memset(&si, 0, sizeof(si));
        si.cbSize = sizeof(si);
        si.fMask  = SIF_POS;
        GetScrollInfo(ctl, SB_CTL, &si);
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", si.nPos);
        return kr_gui_dup(buf);
    }

    char* krGuiScrollbarSet(char* sb_str, char* v_str) {
        HWND ctl = kr_gui_resolve(sb_str);
        if (!ctl) return (char*)"0";
        SCROLLINFO si;
        memset(&si, 0, sizeof(si));
        si.cbSize = sizeof(si);
        si.fMask  = SIF_POS;
        si.nPos   = atoi(v_str ? v_str : "0");
        SetScrollInfo(ctl, SB_CTL, &si, TRUE);
        return (char*)"1";
    }

    // ── Layout helpers (Vertical / Horizontal stacks) ──────────
    //
    // A "stack" is a layout cursor — it remembers parent, starting
    // x/y, the cross-axis size (width for V, height for H), and the
    // gap between widgets. Every guiVNext / guiHNext call returns
    // the NEXT y (or x) and advances the cursor.
    //
    // Krypton-side wrappers around these (guiVLabel, guiVButton, etc.)
    // sit at module level and call kr_gui_stack helpers underneath.
    //
    //   let lay = guiVStack(win, 24, 24, 432, 12)
    //   guiLabel(win, "Name:", guiStackX(lay), guiVNext(lay, 22),
    //            guiStackW(lay), 22)
    //
    // Or use the wrapper helpers (much less repeating yourself):
    //
    //   let lay = guiVStack(win, 24, 24, 432, 12)
    //   guiVLabel(lay, "Name:", 22)
    //   let inp = guiVInput(lay, 30)
    //   let btn = guiVButton(lay, "OK", 36)

    typedef struct {
        HWND parent;        // parent window
        int  x, y;          // origin
        int  cross;         // width (V) or height (H)
        int  gap;
        int  cursor;        // next y (V) or next x (H)
        int  orient;        // 0 = V, 1 = H
        int  right_margin;  // window_w - x - cross at creation
        int  bottom_margin; // window_h - y - cross at creation
        int  elastic;       // reflow on WM_SIZE
    } kr_gui_stack;

    // Global registry so WM_SIZE can iterate every active stack.
    #define KR_GUI_MAX_STACKS 32
    static kr_gui_stack* g_stacks[KR_GUI_MAX_STACKS];
    static int g_n_stacks = 0;

    // Reflow a V-stack: enumerate children of its parent, resize any
    // child whose left edge matches stack.x and width matches the old
    // cross. New cross = client_w - x - right_margin.
    static void kr_gui_stack_reflow_v(kr_gui_stack* s, int new_client_w) {
        if (s->orient != 0 || !s->elastic) return;
        int new_cross = new_client_w - s->x - s->right_margin;
        if (new_cross < 10) new_cross = 10;
        int old_cross = s->cross;
        if (new_cross == old_cross) return;

        HWND child = GetWindow(s->parent, GW_CHILD);
        while (child) {
            RECT r;
            GetWindowRect(child, &r);
            POINT p = { r.left, r.top };
            ScreenToClient(s->parent, &p);
            int child_x = p.x;
            int child_w = r.right - r.left;
            if (child_x == s->x && child_w == old_cross) {
                SetWindowPos(child, NULL, 0, 0, new_cross, r.bottom - r.top,
                             SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
            child = GetWindow(child, GW_HWNDNEXT);
        }
        s->cross = new_cross;
    }

    static void kr_gui_reflow_all(int new_client_w, int new_client_h) {
        (void)new_client_h;
        for (int i = 0; i < g_n_stacks; i++) {
            if (g_stacks[i]) kr_gui_stack_reflow_v(g_stacks[i], new_client_w);
        }
    }

    static kr_gui_stack* kr_gui_stack_resolve(const char* h) {
        if (!h || h[0] != '0' || h[1] != 'x') return NULL;
        kr_gui_stack* s = NULL;
        sscanf(h, "0x%llx", (unsigned long long*)&s);
        return s;
    }

    static char* kr_gui_stack_alloc(HWND parent, int x, int y, int cross, int gap, int orient) {
        kr_gui_stack* s = (kr_gui_stack*)malloc(sizeof(*s));
        if (!s) return (char*)"0";
        s->parent = parent;
        s->x      = x;
        s->y      = y;
        s->cross  = cross;
        s->gap    = gap;
        s->cursor = (orient == 0) ? y : x;
        s->orient = orient;
        // Capture right/bottom margins so WM_SIZE can compute the new
        // cross width as `client - origin - margin`.
        RECT cr;
        GetClientRect(parent, &cr);
        int client_w = cr.right - cr.left;
        int client_h = cr.bottom - cr.top;
        s->right_margin  = client_w - x - cross;
        s->bottom_margin = client_h - y - cross;
        if (s->right_margin  < 0) s->right_margin  = 0;
        if (s->bottom_margin < 0) s->bottom_margin = 0;
        s->elastic = 1;
        if (g_n_stacks < KR_GUI_MAX_STACKS) g_stacks[g_n_stacks++] = s;
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)s);
        return kr_gui_dup(buf);
    }

    char* krGuiVStack(char* parent_str, char* xs, char* ys, char* ws, char* gs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        return kr_gui_stack_alloc(parent, atoi(xs), atoi(ys), atoi(ws), atoi(gs), 0);
    }

    char* krGuiHStack(char* parent_str, char* xs, char* ys, char* hs, char* gs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        return kr_gui_stack_alloc(parent, atoi(xs), atoi(ys), atoi(hs), atoi(gs), 1);
    }

    char* krGuiVNext(char* stack_str, char* size_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        int cur = s->cursor;
        s->cursor += atoi(size_str ? size_str : "0") + s->gap;
        char buf[16]; snprintf(buf, sizeof(buf), "%d", cur);
        return kr_gui_dup(buf);
    }

    char* krGuiHNext(char* stack_str, char* size_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        int cur = s->cursor;
        s->cursor += atoi(size_str ? size_str : "0") + s->gap;
        char buf[16]; snprintf(buf, sizeof(buf), "%d", cur);
        return kr_gui_dup(buf);
    }

    char* krGuiStackParent(char* stack_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)s->parent);
        return kr_gui_dup(buf);
    }
    char* krGuiStackX(char* stack_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[16]; snprintf(buf, sizeof(buf), "%d", s->x); return kr_gui_dup(buf);
    }
    char* krGuiStackY(char* stack_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[16]; snprintf(buf, sizeof(buf), "%d", s->y); return kr_gui_dup(buf);
    }
    char* krGuiStackW(char* stack_str) {
        // For V stacks the cross axis IS the width; for H stacks the
        // x cursor minus origin gives the layout width-so-far. We
        // expose `cross` here — V=width, H=height. Use guiStackH
        // as the alias for clarity.
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[16]; snprintf(buf, sizeof(buf), "%d", s->cross); return kr_gui_dup(buf);
    }
    char* krGuiStackH(char* stack_str) { return krGuiStackW(stack_str); }
    char* krGuiStackGap(char* stack_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[16]; snprintf(buf, sizeof(buf), "%d", s->gap); return kr_gui_dup(buf);
    }
    char* krGuiStackGapAdd(char* stack_str, char* px_str) {
        kr_gui_stack* s = kr_gui_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        s->cursor += atoi(px_str ? px_str : "0");
        return (char*)"1";
    }

    // ── Image (STATIC w/ SS_BITMAP or SS_ICON) ─────────────────
    //
    // Loads a .bmp or .ico file from disk into a STATIC control.
    // PNG / JPEG aren't built into Win32 — they need GDI+ which is
    // a heavier dep; revisit when there's demand.
    //
    //   guiImage(parent, "logo.bmp", x, y, w, h) → handle
    //   guiImageSet(image, "other.bmp")          → swap
    //
    // Tip: guiPickFolder() / guiOpenFile() pair well with this for a
    // "choose an image" flow.

    static int kr_gui_is_icon_path(const char* path) {
        if (!path) return 0;
        size_t n = strlen(path);
        if (n < 4) return 0;
        return (path[n - 4] == '.' &&
                (path[n - 3] == 'i' || path[n - 3] == 'I') &&
                (path[n - 2] == 'c' || path[n - 2] == 'C') &&
                (path[n - 1] == 'o' || path[n - 1] == 'O')) ? 1 : 0;
    }

    // ── GDI+ dynamic-load shim for PNG / JPEG / GIF / TIFF ─────
    //
    // Win32 LoadImageW handles only .bmp and .ico. Everything else
    // (PNG/JPEG/GIF/TIFF) goes through GDI+. We dynamic-load to avoid
    // adding -lgdiplus to every gcc invocation. Call once; leak the
    // module + token for process lifetime.

    typedef int (WINAPI *kr_gp_startup_t)(ULONG_PTR*, void*, void*);
    typedef int (WINAPI *kr_gp_loadfile_t)(const WCHAR*, void**);
    typedef int (WINAPI *kr_gp_make_hbm_t)(void*, HBITMAP*, COLORREF);
    typedef int (WINAPI *kr_gp_dispose_t)(void*);

    struct kr_gp_input { UINT32 ver; void* cb; BOOL sbt; BOOL sec; };

    static HMODULE          g_gp_mod    = NULL;
    static ULONG_PTR        g_gp_token  = 0;
    static kr_gp_loadfile_t g_gp_load   = NULL;
    static kr_gp_make_hbm_t g_gp_hbm    = NULL;
    static kr_gp_dispose_t  g_gp_dispose= NULL;
    static int              g_gp_inited = 0;

    static int kr_gp_init(void) {
        if (g_gp_inited) return g_gp_mod != NULL && g_gp_load != NULL;
        g_gp_inited = 1;
        g_gp_mod = LoadLibraryA("gdiplus.dll");
        if (!g_gp_mod) return 0;
        kr_gp_startup_t pStartup =
            (kr_gp_startup_t)GetProcAddress(g_gp_mod, "GdiplusStartup");
        g_gp_load    = (kr_gp_loadfile_t)GetProcAddress(g_gp_mod, "GdipLoadImageFromFile");
        g_gp_hbm     = (kr_gp_make_hbm_t)GetProcAddress(g_gp_mod, "GdipCreateHBITMAPFromBitmap");
        g_gp_dispose = (kr_gp_dispose_t) GetProcAddress(g_gp_mod, "GdipDisposeImage");
        if (!pStartup || !g_gp_load || !g_gp_hbm || !g_gp_dispose) return 0;
        struct kr_gp_input in = { 1, NULL, FALSE, FALSE };
        if (pStartup(&g_gp_token, &in, NULL) != 0) return 0;
        return 1;
    }

    static int kr_gui_path_is_bmp_or_ico(const char* path) {
        if (!path) return 0;
        size_t n = strlen(path);
        if (n < 4) return 0;
        const char* e = path + n - 4;
        if (e[0] != '.') return 0;
        char ce[4] = { (char)tolower((unsigned char)e[1]),
                       (char)tolower((unsigned char)e[2]),
                       (char)tolower((unsigned char)e[3]), 0 };
        return (strcmp(ce, "bmp") == 0 || strcmp(ce, "ico") == 0) ? 1 : 0;
    }

    static HANDLE kr_gui_load_image_file(const char* path) {
        if (!path || !*path) return NULL;
        wchar_t* wpath = kr_gui_to_w(path);

        // .bmp / .ico via Win32 LoadImage — fastest, native handle.
        if (kr_gui_path_is_bmp_or_ico(path)) {
            UINT type = kr_gui_is_icon_path(path) ? IMAGE_ICON : IMAGE_BITMAP;
            return LoadImageW(NULL, wpath, type, 0, 0,
                              LR_LOADFROMFILE | LR_DEFAULTSIZE | LR_CREATEDIBSECTION);
        }

        // Everything else — PNG, JPEG, GIF, TIFF, WMF, EMF — via GDI+.
        if (!kr_gp_init()) return NULL;
        void* img = NULL;
        if (g_gp_load(wpath, &img) != 0 || !img) return NULL;
        HBITMAP hbm = NULL;
        g_gp_hbm(img, &hbm, 0);
        g_gp_dispose(img);
        return hbm;
    }

    char* krGuiImage(char* parent_str, char* path, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";

        int icon_path = kr_gui_is_icon_path(path);
        DWORD style = WS_CHILD | WS_VISIBLE |
                      (icon_path ? SS_ICON : (SS_BITMAP | SS_REALSIZECONTROL));

        HWND ctl = CreateWindowExW(
            0, L"STATIC", L"",
            style,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, NULL, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";

        HANDLE img = kr_gui_load_image_file(path);
        if (img) {
            SendMessageW(ctl, STM_SETIMAGE,
                         icon_path ? IMAGE_ICON : IMAGE_BITMAP,
                         (LPARAM)img);
        }
        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)ctl);
        return kr_gui_dup(buf);
    }

    char* krGuiImageSet(char* h_str, char* path) {
        HWND ctl = NULL;
        if (h_str && h_str[0] == '0' && h_str[1] == 'x') {
            sscanf(h_str, "0x%llx", (unsigned long long*)&ctl);
        }
        if (!ctl) return (char*)"0";
        HANDLE img = kr_gui_load_image_file(path);
        if (!img) return (char*)"0";
        UINT t = kr_gui_is_icon_path(path) ? IMAGE_ICON : IMAGE_BITMAP;
        // Free the previous image to avoid leaking on every set.
        HANDLE prev = (HANDLE)SendMessageW(ctl, STM_GETIMAGE, t, 0);
        SendMessageW(ctl, STM_SETIMAGE, t, (LPARAM)img);
        if (prev) {
            if (t == IMAGE_BITMAP) DeleteObject(prev);
            else                   DestroyIcon((HICON)prev);
        }
        return (char*)"1";
    }

    // ── Slider (TRACKBAR) ──────────────────────────────────────
    //
    //   guiSlider(parent, x, y, w, h)        → handle
    //   guiSliderRange(slider, min, max)     → set range (default 0..100)
    //   guiSliderSet(slider, value)          → set position
    //   guiSliderValue(slider)               → read current position
    //   guiOnChange(slider, funcptr(myCB))   → fires while user drags

    char* krGuiSlider(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        HWND ctl = CreateWindowExW(
            0, TRACKBAR_CLASSW, L"",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            TBS_HORZ | TBS_AUTOTICKS,
            atoi(xs), atoi(ys), atoi(ws), atoi(hs),
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        SendMessageW(ctl, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
        SendMessageW(ctl, TBM_SETPOS,   TRUE, 0);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiSliderRange(char* sl_str, char* lo_str, char* hi_str) {
        HWND ctl = kr_gui_resolve(sl_str);
        if (!ctl) return (char*)"0";
        int lo = atoi(lo_str ? lo_str : "0");
        int hi = atoi(hi_str ? hi_str : "100");
        SendMessageW(ctl, TBM_SETRANGE, TRUE, MAKELPARAM(lo, hi));
        return (char*)"1";
    }

    char* krGuiSliderSet(char* sl_str, char* v_str) {
        HWND ctl = kr_gui_resolve(sl_str);
        if (!ctl) return (char*)"0";
        SendMessageW(ctl, TBM_SETPOS, TRUE, atoi(v_str ? v_str : "0"));
        return (char*)"1";
    }

    char* krGuiSliderValue(char* sl_str) {
        HWND ctl = kr_gui_resolve(sl_str);
        if (!ctl) return (char*)"0";
        int v = (int)SendMessageW(ctl, TBM_GETPOS, 0, 0);
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", v);
        return kr_gui_dup(buf);
    }

    // ── Spinbox (UpDown control + buddy EDIT) ──────────────────
    //
    // Pairs an UpDown with an EDIT control. The EDIT renders the
    // value; the UpDown buttons increment/decrement. We track the
    // EDIT as the user-visible handle so guiSpinboxValue reads the
    // typed value back.

    char* krGuiSpinbox(char* parent_str, char* xs, char* ys, char* ws, char* hs) {
        HWND parent = NULL;
        sscanf(parent_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";

        int x = atoi(xs), y = atoi(ys), w = atoi(ws), h = atoi(hs);
        // The EDIT handles its own width minus the UpDown's visual
        // overlay. The UpDown sits over the right edge automatically.
        int edit_id = kr_gui_register_id();
        HWND edit = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"0",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_NUMBER | ES_RIGHT,
            x, y, w, h,
            parent, (HMENU)(LONG_PTR)edit_id, GetModuleHandleA(NULL), NULL);
        if (!edit) return (char*)"0";
        kr_gui_skin(edit);

        int up_id = kr_gui_register_id();
        HWND up = CreateWindowExW(
            0, UPDOWN_CLASSW, L"",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            UDS_AUTOBUDDY | UDS_ALIGNRIGHT | UDS_ARROWKEYS | UDS_SETBUDDYINT,
            0, 0, 0, 0,
            parent, (HMENU)(LONG_PTR)up_id, GetModuleHandleA(NULL), NULL);
        if (!up) return (char*)"0";

        SendMessageW(up, UDM_SETBUDDY, (WPARAM)edit, 0);
        SendMessageW(up, UDM_SETRANGE, 0, MAKELPARAM(100, 0));
        SendMessageW(up, UDM_SETPOS,   0, MAKELPARAM(0, 0));

        char buf[32];
        snprintf(buf, sizeof(buf), "%d", edit_id);
        return kr_gui_dup(buf);
    }

    char* krGuiSpinboxRange(char* sb_str, char* lo_str, char* hi_str) {
        HWND edit = kr_gui_resolve(sb_str);
        if (!edit) return (char*)"0";
        // Find the UpDown buddy by enumerating siblings — it's the
        // window registered with this EDIT as its buddy. Simpler:
        // walk forward by ID until we find the UPDOWN_CLASS.
        HWND parent = GetParent(edit);
        HWND up = NULL;
        wchar_t cls[32];
        for (HWND h = GetWindow(parent, GW_CHILD); h; h = GetWindow(h, GW_HWNDNEXT)) {
            if (!GetClassNameW(h, cls, 31)) continue;
            if (wcscmp(cls, UPDOWN_CLASSW) == 0) {
                if ((HWND)SendMessageW(h, UDM_GETBUDDY, 0, 0) == edit) { up = h; break; }
            }
        }
        if (!up) return (char*)"0";
        int lo = atoi(lo_str ? lo_str : "0");
        int hi = atoi(hi_str ? hi_str : "100");
        // UpDown's MAKELPARAM is (max, min) — swapped from the slider.
        SendMessageW(up, UDM_SETRANGE32, lo, hi);
        return (char*)"1";
    }

    char* krGuiSpinboxSet(char* sb_str, char* v_str) {
        HWND edit = kr_gui_resolve(sb_str);
        if (!edit) return (char*)"0";
        wchar_t buf[32];
        _snwprintf(buf, 31, L"%d", atoi(v_str ? v_str : "0"));
        SetWindowTextW(edit, buf);
        return (char*)"1";
    }

    char* krGuiSpinboxValue(char* sb_str) {
        HWND edit = kr_gui_resolve(sb_str);
        if (!edit) return (char*)"0";
        wchar_t buf[32];
        GetWindowTextW(edit, buf, 31);
        char out[32];
        WideCharToMultiByte(CP_UTF8, 0, buf, -1, out, sizeof(out), NULL, NULL);
        return kr_gui_dup(out);
    }

    // ── Toolbar ────────────────────────────────────────────────
    //
    // Wraps ToolbarWindow32 with stock Windows bitmaps from
    // IDB_STD_SMALL_COLOR. Buttons are added with a label string +
    // an icon name keyword that maps to a STD_* index, e.g. "save"
    // for STD_FILESAVE. Pass "" for a text-only button.
    //
    //   guiToolbar(window)               → handle (auto-pinned to top)
    //   guiToolButton(tb, label, icon)   → control id (wire with guiOnClick)
    //   guiToolSep(tb)                   → separator
    //
    // The toolbar pins itself to the top edge and resizes with the
    // window via TB_AUTOSIZE on parent WM_SIZE.

    static int kr_gui_std_icon_idx(const char* name) {
        if (!name || !*name) return -1;
        if (!_stricmp(name, "cut"))    return STD_CUT;        /* 0 */
        if (!_stricmp(name, "copy"))   return STD_COPY;       /* 1 */
        if (!_stricmp(name, "paste"))  return STD_PASTE;      /* 2 */
        if (!_stricmp(name, "undo"))   return STD_UNDO;       /* 3 */
        if (!_stricmp(name, "redo"))   return STD_REDOW;      /* 4 */
        if (!_stricmp(name, "delete")) return STD_DELETE;     /* 5 */
        if (!_stricmp(name, "new"))    return STD_FILENEW;    /* 6 */
        if (!_stricmp(name, "open"))   return STD_FILEOPEN;   /* 7 */
        if (!_stricmp(name, "save"))   return STD_FILESAVE;   /* 8 */
        if (!_stricmp(name, "print"))  return STD_PRINT;      /* 14 */
        if (!_stricmp(name, "find"))   return STD_FIND;       /* 12 */
        if (!_stricmp(name, "replace"))return STD_REPLACE;    /* 13 */
        if (!_stricmp(name, "help"))   return STD_HELP;       /* 11 */
        if (!_stricmp(name, "props"))  return STD_PROPERTIES; /* 10 */
        return -1;
    }

    char* krGuiToolbar(char* window_str) {
        HWND parent = NULL;
        sscanf(window_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";

        HWND tb = CreateWindowExW(
            0, TOOLBARCLASSNAMEW, NULL,
            WS_CHILD | WS_VISIBLE | TBSTYLE_FLAT |
            TBSTYLE_TOOLTIPS | TBSTYLE_LIST | CCS_TOP,
            0, 0, 0, 0,
            parent, (HMENU)(LONG_PTR)kr_gui_register_id(),
            GetModuleHandleA(NULL), NULL);
        if (!tb) return (char*)"0";

        // The TB_BUTTONSTRUCTSIZE sentinel is required since Win95.
        SendMessageW(tb, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);

        // Load the standard small-icon image list (cut/copy/paste/etc.).
        TBADDBITMAP tbab;
        tbab.hInst = HINST_COMMCTRL;
        tbab.nID   = IDB_STD_SMALL_COLOR;
        SendMessageW(tb, TB_ADDBITMAP, 0, (LPARAM)&tbab);

        // Allow text labels to live beside the bitmaps (LIST style).
        SendMessageW(tb, TB_SETMAXTEXTROWS, 1, 0);

        kr_gui_skin(tb);
        g_toolbar = tb;
        SendMessageW(tb, TB_AUTOSIZE, 0, 0);

        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)tb);
        return kr_gui_dup(buf);
    }

    char* krGuiToolButton(char* tb_str, char* label, char* iconName) {
        HWND tb = NULL;
        sscanf(tb_str, "0x%llx", (unsigned long long*)&tb);
        if (!tb) return (char*)"0";

        int icon = kr_gui_std_icon_idx(iconName);
        int id = kr_gui_register_id();

        // Add the label as a string resource the toolbar tracks
        // internally — TBBUTTON.iString takes the index returned.
        wchar_t* wlabel = kr_gui_to_w(label ? label : "");
        INT_PTR str_idx = SendMessageW(tb, TB_ADDSTRINGW, 0, (LPARAM)wlabel);

        TBBUTTON btn;
        memset(&btn, 0, sizeof(btn));
        btn.iBitmap   = icon;
        btn.idCommand = id;
        btn.fsState   = TBSTATE_ENABLED;
        btn.fsStyle   = (icon >= 0) ? (BTNS_BUTTON | BTNS_AUTOSIZE)
                                    : (BTNS_BUTTON | BTNS_AUTOSIZE | BTNS_SHOWTEXT);
        btn.iString   = str_idx;
        SendMessageW(tb, TB_ADDBUTTONS, 1, (LPARAM)&btn);
        SendMessageW(tb, TB_AUTOSIZE,  0, 0);

        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiToolSep(char* tb_str) {
        HWND tb = NULL;
        sscanf(tb_str, "0x%llx", (unsigned long long*)&tb);
        if (!tb) return (char*)"0";
        TBBUTTON btn;
        memset(&btn, 0, sizeof(btn));
        btn.fsStyle = BTNS_SEP;
        SendMessageW(tb, TB_ADDBUTTONS, 1, (LPARAM)&btn);
        SendMessageW(tb, TB_AUTOSIZE,  0, 0);
        return (char*)"1";
    }

    char* krGuiToolbarHeight(char* tb_str) {
        HWND tb = NULL;
        sscanf(tb_str, "0x%llx", (unsigned long long*)&tb);
        if (!tb) return (char*)"0";
        RECT r;
        GetWindowRect(tb, &r);
        char buf[16];
        snprintf(buf, sizeof(buf), "%ld", (long)(r.bottom - r.top));
        return kr_gui_dup(buf);
    }

    // ── Status bar ─────────────────────────────────────────────
    //
    // Wraps msctls_statusbar32 with a parts/text/icon/colour API.
    // Auto-resizes on parent WM_SIZE (handled in kr_gui_proc).
    //
    //   guiStatusBar(window)                 → handle
    //   guiStatusParts(bar, "200,400,-1")    → 3 parts; -1 stretches to right edge
    //   guiStatusSet(bar, idx, text)         → cell text
    //   guiStatusGet(bar, idx)               → cell text (read back)
    //   guiStatusIcon(bar, idx, name)        → "info" | "warning" | "error" |
    //                                          "ok" | "" (clear)
    //   guiStatusBgColor(bar, "0xRRGGBB")    → background tint
    //
    // The status bar carries an HICON per part so the icon API doesn't
    // need extra plumbing.

    static COLORREF g_status_bg = (COLORREF)-1;       // -1 = system default
    static char     g_status_spec[256] = "";           // user's part-widths spec, re-applied on every WM_SIZE

    // Re-apply g_status_spec against the bar's CURRENT client width.
    // Spec syntax (comma-separated cells):
    //   N      — fixed pixel width (e.g. 200)
    //   N%     — percent of bar width (e.g. 25%)
    //   *      — stretchable; leftover divided equally among * cells
    //   -1     — legacy alias for *; stretches one cell to the right
    static void kr_gui_apply_parts(void) {
        if (!g_status_bar || !g_status_spec[0]) return;
        RECT r;
        GetClientRect(g_status_bar, &r);
        int total = r.right - r.left;
        if (total <= 0) return;

        int specs[64];        // -1 = stretch, >= 0 = pixels
        int n = 0;
        int fixed_sum = 0;
        int star_count = 0;
        const char* p = g_status_spec;
        while (n < 64 && *p) {
            while (*p == ' ' || *p == '\t') p++;
            if (!*p) break;
            if (*p == '*') {
                specs[n++] = -1; star_count++; p++;
            } else if (*p == '-') {
                specs[n++] = -1; star_count++;
                p++;
                while (*p >= '0' && *p <= '9') p++;
            } else if (*p >= '0' && *p <= '9') {
                int v = 0;
                while (*p >= '0' && *p <= '9') { v = v * 10 + (*p - '0'); p++; }
                if (*p == '%') {
                    v = (total * v) / 100;
                    p++;
                }
                specs[n++] = v;
                fixed_sum += v;
            } else {
                p++; continue;
            }
            if (*p == ',') p++;
        }
        if (n == 0) return;

        int star_w = 0;
        if (star_count > 0) {
            int leftover = total - fixed_sum;
            if (leftover < 0) leftover = 0;
            star_w = leftover / star_count;
        }

        int parts[64];
        int running = 0;
        for (int i = 0; i < n; i++) {
            if (specs[i] == -1) running += star_w;
            else                running += specs[i];
            parts[i] = running;
        }
        // Pin last part to the right edge regardless of rounding.
        parts[n - 1] = -1;
        SendMessageW(g_status_bar, SB_SETPARTS, n, (LPARAM)parts);
    }

    static HICON kr_gui_load_status_icon(const char* name) {
        if (!name || !*name) return NULL;
        LPCWSTR id = NULL;
        if      (!_stricmp(name, "info"))    id = IDI_INFORMATION;
        else if (!_stricmp(name, "warning")) id = IDI_WARNING;
        else if (!_stricmp(name, "error"))   id = IDI_ERROR;
        else if (!_stricmp(name, "ok"))      id = IDI_ASTERISK;
        else if (!_stricmp(name, "question"))id = IDI_QUESTION;
        else return NULL;
        return LoadIconW(NULL, id);
    }

    char* krGuiStatusBar(char* window_str) {
        HWND parent = NULL;
        sscanf(window_str, "%p", (void**)&parent);
        if (!parent) return (char*)"0";
        int id = kr_gui_register_id();
        HWND ctl = CreateWindowExW(
            0, STATUSCLASSNAMEW, L"",
            WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
            0, 0, 0, 0,
            parent, (HMENU)(LONG_PTR)id, GetModuleHandleA(NULL), NULL);
        if (!ctl) return (char*)"0";
        kr_gui_skin(ctl);
        g_status_bar = ctl;
        // Default to 1 part stretching the full width.
        int single = -1;
        SendMessageW(ctl, SB_SETPARTS, 1, (LPARAM)&single);
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", id);
        return kr_gui_dup(buf);
    }

    char* krGuiStatusParts(char* bar_str, char* widths) {
        HWND ctl = kr_gui_resolve(bar_str);
        if (!ctl || !widths) return (char*)"0";
        // Save the user's spec; kr_gui_apply_parts re-applies it on
        // every WM_SIZE so percentages and `*` stretchers track the
        // current bar width.
        size_t n = strlen(widths);
        if (n >= sizeof(g_status_spec)) n = sizeof(g_status_spec) - 1;
        memcpy(g_status_spec, widths, n);
        g_status_spec[n] = 0;
        kr_gui_apply_parts();
        return (char*)"1";
    }

    char* krGuiStatusSet(char* bar_str, char* idx_str, char* text) {
        HWND ctl = kr_gui_resolve(bar_str);
        if (!ctl) return (char*)"0";
        int idx = atoi(idx_str ? idx_str : "0");
        wchar_t* w = kr_gui_to_w(text ? text : "");
        SendMessageW(ctl, SB_SETTEXTW, idx, (LPARAM)w);
        return (char*)"1";
    }

    char* krGuiStatusGet(char* bar_str, char* idx_str) {
        HWND ctl = kr_gui_resolve(bar_str);
        if (!ctl) return (char*)"";
        int idx = atoi(idx_str ? idx_str : "0");
        wchar_t buf[1024];
        SendMessageW(ctl, SB_GETTEXTW, idx, (LPARAM)buf);
        return kr_gui_to_u(buf);
    }

    char* krGuiStatusIcon(char* bar_str, char* idx_str, char* iconName) {
        HWND ctl = kr_gui_resolve(bar_str);
        if (!ctl) return (char*)"0";
        int idx = atoi(idx_str ? idx_str : "0");
        HICON ic = kr_gui_load_status_icon(iconName);
        SendMessageW(ctl, SB_SETICON, idx, (LPARAM)ic);
        return (char*)"1";
    }

    char* krGuiStatusBgColor(char* bar_str, char* hex) {
        HWND ctl = kr_gui_resolve(bar_str);
        if (!ctl) return (char*)"0";
        // Parse "#RRGGBB" or "0xRRGGBB" or "RRGGBB".
        const char* p = hex ? hex : "";
        if (*p == '#') p++;
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
        unsigned int v = 0;
        sscanf(p, "%x", &v);
        COLORREF c = RGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);

        // Common Controls v6 themed status bar paints over SB_SETBKCOLOR.
        // Disable the theme on this window so the SET sticks. We lose
        // the subtle modern gradient, but the user explicitly asked
        // for a tint — that's the trade.
        HMODULE ux = LoadLibraryA("uxtheme.dll");
        if (ux) {
            typedef HRESULT (WINAPI *SetWindowTheme_t)(HWND, LPCWSTR, LPCWSTR);
            SetWindowTheme_t pSet = (SetWindowTheme_t)
                GetProcAddress(ux, "SetWindowTheme");
            if (pSet) pSet(ctl, L"", L"");
        }

        SendMessageW(ctl, SB_SETBKCOLOR, 0, (LPARAM)c);
        g_status_bg = c;
        InvalidateRect(ctl, NULL, TRUE);
        return (char*)"1";
    }

    // ── File dialogs ───────────────────────────────────────────
    //
    // GetOpenFileNameA / GetSaveFileNameA from comdlg32. Filter spec
    // is a comma-separated list of "label|*.ext;*.ext2" entries:
    //
    //   "Krypton (*.k)|*.k,All Files|*.*"
    //
    // The internal Win32 format wants null-separated pairs ending
    // with a double null, which we build below from the simpler CSV.

    // Builds a UTF-16 filter string for GetOpenFileNameW: pairs of
    // null-terminated strings, ended by an extra null. Caller passes
    // a CSV like "Krypton (*.k)|*.k,All Files|*.*".
    static void kr_gui_build_filter_w(const char* csv, wchar_t* out, size_t cap_chars) {
        size_t pos = 0;
        const char* effective = (csv && *csv) ? csv : "All Files|*.*";
        const char* p = effective;
        while (*p && pos + 2 < cap_chars) {
            const char* bar = strchr(p, '|');
            const char* end = strchr(p, ',');
            if (!end) end = p + strlen(p);

            const char* lab_s; size_t lab_n;
            const char* pat_s; size_t pat_n;
            if (!bar || bar > end) {
                lab_s = p; lab_n = end - p;
                pat_s = p; pat_n = end - p;
            } else {
                lab_s = p;       lab_n = bar - p;
                pat_s = bar + 1; pat_n = end - (bar + 1);
            }
            // Convert label
            char tmp[256];
            size_t cn = lab_n < sizeof(tmp) - 1 ? lab_n : sizeof(tmp) - 1;
            memcpy(tmp, lab_s, cn); tmp[cn] = 0;
            int wn = MultiByteToWideChar(CP_UTF8, 0, tmp, -1,
                                         out + pos, (int)(cap_chars - pos));
            if (wn > 0) pos += wn;     // includes trailing null
            // Convert pattern
            cn = pat_n < sizeof(tmp) - 1 ? pat_n : sizeof(tmp) - 1;
            memcpy(tmp, pat_s, cn); tmp[cn] = 0;
            wn = MultiByteToWideChar(CP_UTF8, 0, tmp, -1,
                                     out + pos, (int)(cap_chars - pos));
            if (wn > 0) pos += wn;

            if (*end == ',') p = end + 1;
            else break;
        }
        if (pos < cap_chars) out[pos++] = 0;     // double-null terminator
    }

    char* krGuiOpenFile(char* title, char* filterCsv) {
        wchar_t filter[1024];
        memset(filter, 0, sizeof(filter));
        kr_gui_build_filter_w(filterCsv, filter, 1024);

        wchar_t path[2048] = {0};
        wchar_t* wtitle = kr_gui_to_w((title && *title) ? title : "Open File");
        OPENFILENAMEW ofn;
        memset(&ofn, 0, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner   = g_main_hwnd;
        ofn.lpstrFilter = filter;
        ofn.lpstrFile   = path;
        ofn.nMaxFile    = 2048;
        ofn.lpstrTitle  = wtitle;
        ofn.Flags       = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY |
                          OFN_NOCHANGEDIR;
        if (!GetOpenFileNameW(&ofn)) return (char*)"";
        return kr_gui_to_u(path);
    }

    char* krGuiSaveFile(char* title, char* filterCsv, char* defaultName) {
        wchar_t filter[1024];
        memset(filter, 0, sizeof(filter));
        kr_gui_build_filter_w(filterCsv, filter, 1024);

        wchar_t path[2048] = {0};
        if (defaultName && *defaultName) {
            wchar_t* wn = kr_gui_to_w(defaultName);
            wcsncpy(path, wn, 2047);
        }
        wchar_t* wtitle = kr_gui_to_w((title && *title) ? title : "Save File");
        OPENFILENAMEW ofn;
        memset(&ofn, 0, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner   = g_main_hwnd;
        ofn.lpstrFilter = filter;
        ofn.lpstrFile   = path;
        ofn.nMaxFile    = 2048;
        ofn.lpstrTitle  = wtitle;
        ofn.Flags       = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY |
                          OFN_NOCHANGEDIR;
        if (!GetSaveFileNameW(&ofn)) return (char*)"";
        return kr_gui_to_u(path);
    }

    char* krGuiPickFolder(char* title) {
        BROWSEINFOW bi;
        memset(&bi, 0, sizeof(bi));
        bi.hwndOwner = g_main_hwnd;
        bi.lpszTitle = kr_gui_to_w((title && *title) ? title : "Pick a folder");
        bi.ulFlags   = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
        LPITEMIDLIST pidl = SHBrowseForFolderW(&bi);
        if (!pidl) return (char*)"";
        wchar_t path[MAX_PATH] = {0};
        SHGetPathFromIDListW(pidl, path);
        IMalloc* alloc = NULL;
        if (SHGetMalloc(&alloc) == S_OK) {
            alloc->lpVtbl->Free(alloc, pidl);
            alloc->lpVtbl->Release(alloc);
        }
        return kr_gui_to_u(path);
    }

    char* krGuiSetText(char* hwnd_str, char* text) {
        HWND ctl = NULL;
        // Accept either a hex pointer or a decimal id (button case).
        if (hwnd_str && hwnd_str[0] == '0' && hwnd_str[1] == 'x') {
            sscanf(hwnd_str, "%p", (void**)&ctl);
        } else {
            int id = atoi(hwnd_str ? hwnd_str : "0");
            if (id >= 1000 && g_main_hwnd) ctl = GetDlgItem(g_main_hwnd, id);
            else sscanf(hwnd_str, "%p", (void**)&ctl);
        }
        if (!ctl) return (char*)"0";
        wchar_t* w = kr_gui_to_w(text ? text : "");
        SetWindowTextW(ctl, w);
        return (char*)"1";
    }

    char* krGuiGetText(char* hwnd_str) {
        HWND ctl = NULL;
        if (hwnd_str && hwnd_str[0] == '0' && hwnd_str[1] == 'x') {
            sscanf(hwnd_str, "%p", (void**)&ctl);
        } else {
            int id = atoi(hwnd_str ? hwnd_str : "0");
            if (id >= 1000 && g_main_hwnd) ctl = GetDlgItem(g_main_hwnd, id);
            else sscanf(hwnd_str, "%p", (void**)&ctl);
        }
        if (!ctl) return (char*)"";
        wchar_t buf[2048];
        GetWindowTextW(ctl, buf, sizeof(buf) / sizeof(wchar_t));
        return kr_gui_to_u(buf);
    }

    char* krGuiOnClick(char* id_str, char* sinkPtr) {
        int id = atoi(id_str ? id_str : "0");
        int slot = id - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return (char*)"0";
        g_cb[slot] = (kr_gui_cb)sinkPtr;
        return (char*)"1";
    }

    char* krGuiMessageBox(char* title, char* msg) {
        wchar_t* wmsg   = kr_gui_to_w(msg   ? msg   : "");
        wchar_t* wtitle = kr_gui_to_w(title ? title : "Krypton");
        MessageBoxW(g_main_hwnd, wmsg, wtitle, MB_OK | MB_ICONINFORMATION);
        return (char*)"1";
    }

    char* krGuiRun(void) {
        MSG msg;
        while (GetMessageW(&msg, NULL, 0, 0) > 0) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        return (char*)"0";
    }

    char* krGuiQuit(void) {
        PostQuitMessage(0);
        return (char*)"1";
    }

#elif defined(__APPLE__)
    // ──────────────────────────────────────────────────────────────────
    // macOS — Cocoa via the Objective-C runtime C API.
    //
    // We talk to AppKit through objc_msgSend rather than embedding .m
    // sources so kcc's plain `.c → clang` pipeline still works. Link
    // line on macOS:
    //   clang gui.c -o gui -Wl,-framework,Cocoa -lobjc -lm -w
    // (kcc.sh already passes -Wl,… through unchanged.)
    //
    // Implements the same krGui* API surface as the Win32 path. Widgets
    // not yet wired return empty handles so existing programs link and
    // run; they just don't render those widgets.
    //
    // First slice: window, label, text input, button, message box,
    // init/show/run/quit, onClick, set/getText. Everything else is a
    // no-op stub for now and will be filled in incrementally.
    // ──────────────────────────────────────────────────────────────────

    #include <objc/objc.h>
    #include <objc/runtime.h>
    #include <objc/message.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    // Hand-roll the geometry types so we don't pull in CoreGraphics.h.
    // 64-bit only — modern macOS (Apple Silicon + recent Intel) is LP64.
    typedef struct { double x, y; } KRPoint;
    typedef struct { double width, height; } KRSize;
    typedef struct { KRPoint origin; KRSize size; } KRRect;

    // NSWindowStyleMask bits and NSBackingStoreType.
    #define KR_NS_TITLED       1UL
    #define KR_NS_CLOSABLE     2UL
    #define KR_NS_MINIATURIZE  4UL
    #define KR_NS_RESIZABLE    8UL
    #define KR_NS_BACKING_BUF  2UL

    // objc_msgSend isn't typed — every call site has to cast it to the
    // exact (id, SEL, …) signature so the compiler emits the right ABI
    // sequence. These shorthands cover the common shapes.
    #define MSG_V(o, s)         ((void(*)(id,SEL))objc_msgSend)((o),(s))
    #define MSG_O(o, s)         ((id  (*)(id,SEL))objc_msgSend)((o),(s))
    #define MSG_O_O(o, s, a)    ((id  (*)(id,SEL,id))objc_msgSend)((o),(s),(a))
    #define MSG_V_O(o, s, a)    ((void(*)(id,SEL,id))objc_msgSend)((o),(s),(a))
    #define MSG_V_L(o, s, a)    ((void(*)(id,SEL,long))objc_msgSend)((o),(s),(a))
    #define MSG_V_C(o, s, a)    ((void(*)(id,SEL,signed char))objc_msgSend)((o),(s),(a))
    #define MSG_V_SEL(o, s, a)  ((void(*)(id,SEL,SEL))objc_msgSend)((o),(s),(a))
    #define MSG_L(o, s)         ((long(*)(id,SEL))objc_msgSend)((o),(s))

    typedef signed char KR_BOOL;

    // -[KrFlippedView isFlipped] returns YES so child-view coordinates
    // run top-down, matching Krypton's Win32-shaped (x, y) API.
    static KR_BOOL kr_view_is_flipped(id self, SEL _cmd) {
        (void)self; (void)_cmd;
        return 1;
    }

    // Click / change dispatch tables — slot N holds the Krypton sink
    // for the control with tag (1000 + N). Win32 splits click events
    // (WM_COMMAND) and change events (WM_HSCROLL, WM_NOTIFY) by message
    // type; Cocoa funnels everything through one target/action, so we
    // keep two slot tables and fire whichever the user wired. Same
    // semantics, different bookkeeping.
    typedef char* (*kr_gui_cb)(void);
    #define KR_GUI_MAX_CB 256
    static kr_gui_cb g_cb[KR_GUI_MAX_CB];
    static kr_gui_cb g_change_cb[KR_GUI_MAX_CB];
    static int g_next_id = 1000;

    static id  g_app           = NULL;
    static id  g_main_window   = NULL;
    static id  g_content_view  = NULL;
    static id  g_target        = NULL;   // shared NSObject for target/action
    static id  g_tab_delegate  = NULL;   // shared NSTabView delegate (selection-changed)
    static id  g_tree_helper   = NULL;   // shared NSOutlineView data-source + delegate
    static id  g_menu_bar      = NULL;   // [NSApp setMainMenu:] target, lazily created
    static int g_inited        = 0;

    // Forward declarations — the tag/text helpers are defined further
    // down with the other plumbing, but the dispatch impls below need
    // them. Bodies live near kr_obj_from / kr_ns_to_c.
    static void kr_set_widget_tag(id ctl, long tag);
    static long kr_get_widget_tag(id ctl);

    // Shared action method — looked up by sender tag so one selector
    // can serve every wired control in the program. Fires onClick if
    // wired, then onChange if wired (matches Win32 single-event flow
    // when only one is set; double-wiring fires both intentionally).
    static void kr_action_imp(id self, SEL _cmd, id sender) {
        (void)self; (void)_cmd;
        if (!sender) return;
        long tag = kr_get_widget_tag(sender);
        int slot = (int)tag - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return;
        if (g_cb[slot])        g_cb[slot]();
        if (g_change_cb[slot]) g_change_cb[slot]();
    }

    // Shared tab-view delegate — NSTabView fires
    // -tabView:didSelectTabViewItem: on selection change rather than
    // routing through target/action, so we plumb it the same way as
    // kr_action_imp but with the right method signature.
    static void kr_tab_change_imp(id self, SEL _cmd, id tabview, id item) {
        (void)self; (void)_cmd; (void)item;
        if (!tabview) return;
        long tag = kr_get_widget_tag(tabview);
        int slot = (int)tag - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return;
        if (g_change_cb[slot]) g_change_cb[slot]();
        else if (g_cb[slot])   g_cb[slot]();
    }

    // ── Dock manager (top/bottom/left/right/fill, edge-eating) ───
    //
    // Mirrors the Win32 dock manager: each dock owns a list of kids
    // tagged with a side and a fixed size. krGuiDockApply lays them
    // out by walking the kids in declaration order, eating edges off
    // the contentView's bounds, then giving the leftover to fill.
    // NSWindowDidResizeNotification re-fires the layout so panels
    // reflow when the user resizes the window.
    typedef struct {
        id  view;            // NSView the user mounted
        int side;            // 0=top, 1=bottom, 2=left, 3=right, 4=fill
        int size;
    } kr_dock_kid;

    typedef struct {
        id          window;        // NSWindow*
        id          content;       // NSView* (cached contentView)
        kr_dock_kid kids[64];
        int         n_kids;
    } kr_dock_state;

    #define KR_GUI_MAX_DOCKS 8
    static kr_dock_state* g_docks[KR_GUI_MAX_DOCKS];
    static int g_n_docks = 0;

    static void kr_dock_layout(kr_dock_state* d) {
        if (!d || !d->content) return;
        KRRect cf = ((KRRect(*)(id,SEL))objc_msgSend)(d->content, sel_getUid("bounds"));
        double top = 0, bot = cf.size.height, lft = 0, rgt = cf.size.width;
        for (int i = 0; i < d->n_kids; i++) {
            kr_dock_kid* c = &d->kids[i];
            if (!c->view || c->side == 4) continue;
            KRRect r;
            if (c->side == 0) {           // top — eat from top edge
                r = (KRRect){{ lft, top }, { rgt - lft, (double)c->size }};
                top += c->size;
            } else if (c->side == 1) {    // bottom — eat from bottom edge
                r = (KRRect){{ lft, bot - c->size }, { rgt - lft, (double)c->size }};
                bot -= c->size;
            } else if (c->side == 2) {    // left — eat from left edge
                r = (KRRect){{ lft, top }, { (double)c->size, bot - top }};
                lft += c->size;
            } else {                      // right — eat from right edge
                r = (KRRect){{ rgt - c->size, top }, { (double)c->size, bot - top }};
                rgt -= c->size;
            }
            ((void(*)(id,SEL,KRRect))objc_msgSend)(c->view, sel_getUid("setFrame:"), r);
        }
        // Fill consumes whatever's left after edge eaters.
        for (int i = 0; i < d->n_kids; i++) {
            kr_dock_kid* c = &d->kids[i];
            if (c->side == 4 && c->view) {
                KRRect r = {{ lft, top }, { rgt - lft, bot - top }};
                ((void(*)(id,SEL,KRRect))objc_msgSend)(c->view, sel_getUid("setFrame:"), r);
            }
        }
    }

    // NSNotificationCenter selector — fires on NSWindowDidResizeNotification.
    // Walks every registered dock and re-lays out the ones whose owning
    // window matches. Single shared selector keeps the observer count low.
    static void kr_dock_resize_imp(id self, SEL _cmd, id notification) {
        (void)self; (void)_cmd;
        if (!notification) return;
        id window = MSG_O(notification, sel_getUid("object"));
        for (int i = 0; i < g_n_docks; i++) {
            if (g_docks[i] && g_docks[i]->window == window) {
                kr_dock_layout(g_docks[i]);
            }
        }
    }

    // Spinbox action — NSStepper sender. Each spinbox is a composite
    // (NSStepper paired with an NSTextField); the textfield is wired
    // to the stepper as an associated object so the action can mirror
    // the new integer into the visible text and fire user callbacks.
    static char kr_spin_partner_key;        // associated-object key

    static void kr_spin_action_imp(id self, SEL _cmd, id stepper) {
        (void)self; (void)_cmd;
        if (!stepper) return;
        id tf = (id)objc_getAssociatedObject(stepper, &kr_spin_partner_key);
        if (tf) {
            long v = MSG_L(stepper, sel_getUid("integerValue"));
            char buf[32];
            snprintf(buf, sizeof(buf), "%ld", v);
            MSG_V_O(tf, sel_getUid("setStringValue:"),
                    ((id(*)(id,SEL,const char*))objc_msgSend)(
                        (id)objc_getClass("NSString"),
                        sel_getUid("stringWithUTF8String:"),
                        buf));
        }
        long tag = kr_get_widget_tag(stepper);
        int slot = (int)tag - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return;
        if (g_change_cb[slot]) g_change_cb[slot]();
        else if (g_cb[slot])   g_cb[slot]();
    }

    // Splitter — thin draggable bar matching the Win32 contract: a
    // standalone STATIC the user drags to resize sibling panels. We
    // build a KrSplitter NSView subclass that overrides mouseDown:,
    // mouseDragged:, drawRect:, and isFlipped (so the bar's parent is
    // assumed flipped, top-left coords).
    typedef struct {
        int    orient;             // 0 = horizontal bar (drag y), 1 = vertical bar (drag x)
        int    pos;                // current top (h) or left (v) in parent coords
        double drag_start_mouse;   // mouse coord at mouseDown (window coords)
        int    drag_start_pos;     // splitter pos at mouseDown
    } kr_split_state;
    static char kr_split_state_key;

    static void kr_split_mouseDown_imp(id self, SEL _cmd, id event) {
        (void)_cmd;
        if (!event) return;
        kr_split_state* s = (kr_split_state*)objc_getAssociatedObject(self, &kr_split_state_key);
        if (!s) return;
        // -[NSEvent locationInWindow] returns NSPoint (16 bytes — fits
        // in registers on both arm64 and x86_64, so plain objc_msgSend
        // is correct without _stret.).
        KRPoint loc = ((KRPoint(*)(id,SEL))objc_msgSend)(event, sel_getUid("locationInWindow"));
        s->drag_start_mouse = (s->orient == 0) ? loc.y : loc.x;
        s->drag_start_pos   = s->pos;
    }

    static void kr_split_mouseDragged_imp(id self, SEL _cmd, id event) {
        (void)_cmd;
        if (!event) return;
        kr_split_state* s = (kr_split_state*)objc_getAssociatedObject(self, &kr_split_state_key);
        if (!s) return;
        KRPoint loc = ((KRPoint(*)(id,SEL))objc_msgSend)(event, sel_getUid("locationInWindow"));
        double cur = (s->orient == 0) ? loc.y : loc.x;
        int delta = (int)(cur - s->drag_start_mouse);
        // Window coords are bottom-up; our flipped contentView is
        // top-down. For the horizontal bar (drag y) we flip the sign so
        // the bar visually tracks the cursor. The vertical bar's x is
        // already aligned.
        if (s->orient == 0) delta = -delta;
        int newpos = s->drag_start_pos + delta;
        if (newpos < 0) newpos = 0;
        s->pos = newpos;

        KRRect r = ((KRRect(*)(id,SEL))objc_msgSend)(self, sel_getUid("frame"));
        if (s->orient == 0) r.origin.y = (double)newpos;
        else                r.origin.x = (double)newpos;
        ((void(*)(id,SEL,KRRect))objc_msgSend)(self, sel_getUid("setFrame:"), r);

        long tag = kr_get_widget_tag(self);
        int slot = (int)tag - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return;
        if (g_change_cb[slot]) g_change_cb[slot]();
        else if (g_cb[slot])   g_cb[slot]();
    }

    // ── Tree view (NSOutlineView) data source / delegate ─────────
    //
    // One shared helper class implements the four NSOutlineView
    // data-source selectors plus the selection-change delegate hook.
    // Each tree's nodes are NSMutableDictionary {label, children}; the
    // root array hangs off the outline view via associated objects.
    static char kr_tree_root_key;

    static long kr_tree_num_children_imp(id self, SEL _cmd, id outline, id item) {
        (void)self; (void)_cmd;
        if (item == NULL) {
            id root = (id)objc_getAssociatedObject(outline, &kr_tree_root_key);
            return root ? MSG_L(root, sel_getUid("count")) : 0;
        }
        id ch = ((id(*)(id,SEL,id))objc_msgSend)(item, sel_getUid("objectForKey:"),
            ((id(*)(id,SEL,const char*))objc_msgSend)(
                (id)objc_getClass("NSString"),
                sel_getUid("stringWithUTF8String:"),
                "children"));
        return ch ? MSG_L(ch, sel_getUid("count")) : 0;
    }

    static id kr_tree_child_imp(id self, SEL _cmd, id outline, long idx, id item) {
        (void)self; (void)_cmd;
        id arr = NULL;
        if (item == NULL) {
            arr = (id)objc_getAssociatedObject(outline, &kr_tree_root_key);
        } else {
            arr = ((id(*)(id,SEL,id))objc_msgSend)(item, sel_getUid("objectForKey:"),
                ((id(*)(id,SEL,const char*))objc_msgSend)(
                    (id)objc_getClass("NSString"),
                    sel_getUid("stringWithUTF8String:"),
                    "children"));
        }
        if (!arr) return NULL;
        return ((id(*)(id,SEL,long))objc_msgSend)(arr, sel_getUid("objectAtIndex:"), idx);
    }

    static signed char kr_tree_is_expandable_imp(id self, SEL _cmd, id outline, id item) {
        (void)self; (void)_cmd; (void)outline;
        if (item == NULL) return 0;
        id ch = ((id(*)(id,SEL,id))objc_msgSend)(item, sel_getUid("objectForKey:"),
            ((id(*)(id,SEL,const char*))objc_msgSend)(
                (id)objc_getClass("NSString"),
                sel_getUid("stringWithUTF8String:"),
                "children"));
        return (ch && MSG_L(ch, sel_getUid("count")) > 0) ? 1 : 0;
    }

    static id kr_tree_object_value_imp(id self, SEL _cmd, id outline, id col, id item) {
        (void)self; (void)_cmd; (void)outline; (void)col;
        if (item == NULL) return NULL;
        return ((id(*)(id,SEL,id))objc_msgSend)(item, sel_getUid("objectForKey:"),
            ((id(*)(id,SEL,const char*))objc_msgSend)(
                (id)objc_getClass("NSString"),
                sel_getUid("stringWithUTF8String:"),
                "label"));
    }

    static void kr_tree_selection_did_change_imp(id self, SEL _cmd, id notification) {
        (void)self; (void)_cmd;
        if (!notification) return;
        id outline = MSG_O(notification, sel_getUid("object"));
        if (!outline) return;
        long tag = kr_get_widget_tag(outline);
        int slot = (int)tag - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return;
        if (g_change_cb[slot]) g_change_cb[slot]();
        else if (g_cb[slot])   g_cb[slot]();
    }

    // Paint the bar a flat tint so it's visible without theming.
    static void kr_split_drawRect_imp(id self, SEL _cmd, KRRect dirty) {
        (void)_cmd; (void)dirty;
        KRRect b = ((KRRect(*)(id,SEL))objc_msgSend)(self, sel_getUid("bounds"));
        id color = MSG_O((id)objc_getClass("NSColor"), sel_getUid("lightGrayColor"));
        MSG_V(color, sel_getUid("set"));
        id path = ((id(*)(id,SEL,KRRect))objc_msgSend)(
            (id)objc_getClass("NSBezierPath"),
            sel_getUid("bezierPathWithRect:"), b);
        MSG_V(path, sel_getUid("fill"));
    }

    // Splitter lives inside the flipped contentView, but its own
    // children (none, in our design) would need top-left coords too;
    // doesn't actually matter here since we don't add subviews. Kept
    // for symmetry with KrFlippedView.
    static KR_BOOL kr_split_isFlipped_imp(id self, SEL _cmd) {
        (void)self; (void)_cmd;
        return 1;
    }

    // Per-call duplicated buffer — same rationale as the Win32 side:
    // handles are immutable identifiers, so callers' Krypton variables
    // shouldn't all alias one static buffer.
    static char* kr_gui_dup(const char* s) {
        size_t n = strlen(s) + 1;
        char* p = (char*)malloc(n);
        if (p) memcpy(p, s, n);
        return p;
    }

    // Format an Objective-C `id` as a hex handle string the Krypton
    // side can pass back through char* parameters.
    static char* kr_handle(id obj) {
        char buf[32];
        snprintf(buf, sizeof(buf), "%p", (void*)obj);
        return kr_gui_dup(buf);
    }

    static id kr_obj_from(const char* s) {
        if (!s || !*s) return NULL;
        void* p = NULL;
        if (sscanf(s, "%p", &p) != 1) return NULL;
        return (id)p;
    }

    // -setTag: lives on NSControl, not NSView, so widgets like NSTabView
    // and our KrSplitter throw on direct setTag:. Route every tag access
    // through these helpers — they call the native selector when it
    // exists and fall back to an associated NSNumber when it doesn't.
    static char kr_tag_fallback_key;

    static void kr_set_widget_tag(id ctl, long tag) {
        if (!ctl) return;
        SEL setTag = sel_getUid("setTag:");
        if (((signed char(*)(id,SEL,SEL))objc_msgSend)(
                ctl, sel_getUid("respondsToSelector:"), setTag)) {
            ((void(*)(id,SEL,long))objc_msgSend)(ctl, setTag, tag);
            return;
        }
        id num = ((id(*)(id,SEL,long))objc_msgSend)(
            (id)objc_getClass("NSNumber"),
            sel_getUid("numberWithLong:"),
            tag);
        objc_setAssociatedObject(ctl, &kr_tag_fallback_key, num, 1);  // RETAIN_NONATOMIC
    }

    static long kr_get_widget_tag(id ctl) {
        if (!ctl) return 0;
        // NSView gained a read-only -tag that returns 0 by default.
        // Real-set values from -setTag: come back here too, so prefer
        // the native getter when it produces a non-zero answer.
        SEL tagSel = sel_getUid("tag");
        if (((signed char(*)(id,SEL,SEL))objc_msgSend)(
                ctl, sel_getUid("respondsToSelector:"), tagSel)) {
            long t = MSG_L(ctl, tagSel);
            if (t != 0) return t;
        }
        id num = (id)objc_getAssociatedObject(ctl, &kr_tag_fallback_key);
        if (num) return MSG_L(num, sel_getUid("longValue"));
        return 0;
    }

    // UTF-8 → autoreleased NSString. AppKit retains as needed.
    static id kr_ns_str(const char* utf8) {
        if (!utf8) utf8 = "";
        return ((id(*)(id,SEL,const char*))objc_msgSend)(
            (id)objc_getClass("NSString"),
            sel_getUid("stringWithUTF8String:"),
            utf8);
    }

    // NSString → newly malloc'd UTF-8 (caller owns).
    static char* kr_ns_to_c(id ns) {
        if (!ns) return kr_gui_dup("");
        const char* p = ((const char*(*)(id,SEL))objc_msgSend)(ns, sel_getUid("UTF8String"));
        return kr_gui_dup(p ? p : "");
    }

    // One-time setup: NSApplication, target/action class, flipped view
    // class. Both krGuiInit and krGuiWindow call this so either entry
    // point is safe.
    static void kr_gui_bootstrap(void) {
        if (g_inited) return;
        g_inited = 1;

        for (int i = 0; i < KR_GUI_MAX_CB; i++) g_cb[i]        = NULL;
        for (int i = 0; i < KR_GUI_MAX_CB; i++) g_change_cb[i] = NULL;

        // [NSApplication sharedApplication]
        g_app = MSG_O((id)objc_getClass("NSApplication"), sel_getUid("sharedApplication"));
        // setActivationPolicy:NSApplicationActivationPolicyRegular (= 0)
        MSG_V_L(g_app, sel_getUid("setActivationPolicy:"), 0);

        // Build a small NSObject subclass that holds our target/action
        // method. Using the runtime API keeps everything in plain C.
        Class targetCls = objc_allocateClassPair((Class)objc_getClass("NSObject"), "KrGuiTarget", 0);
        if (targetCls) {
            class_addMethod(targetCls, sel_getUid("krAction:"),     (IMP)kr_action_imp,      "v@:@");
            class_addMethod(targetCls, sel_getUid("krSpinAction:"), (IMP)kr_spin_action_imp, "v@:@");
            class_addMethod(targetCls, sel_getUid("krDockResize:"), (IMP)kr_dock_resize_imp, "v@:@");
            objc_registerClassPair(targetCls);
        } else {
            targetCls = (Class)objc_getClass("KrGuiTarget");
        }
        g_target = MSG_O(MSG_O((id)targetCls, sel_getUid("alloc")), sel_getUid("init"));

        // NSTabView delegate — separate class because the selector
        // signature differs from target/action.
        Class tabCls = objc_allocateClassPair((Class)objc_getClass("NSObject"), "KrTabDelegate", 0);
        if (tabCls) {
            class_addMethod(tabCls, sel_getUid("tabView:didSelectTabViewItem:"),
                            (IMP)kr_tab_change_imp, "v@:@@");
            objc_registerClassPair(tabCls);
        } else {
            tabCls = (Class)objc_getClass("KrTabDelegate");
        }
        g_tab_delegate = MSG_O(MSG_O((id)tabCls, sel_getUid("alloc")), sel_getUid("init"));

        // Flipped NSView — top-left origin so subviews lay out the way
        // our (x, y) API documents.
        Class flipped = objc_allocateClassPair((Class)objc_getClass("NSView"), "KrFlippedView", 0);
        if (flipped) {
            class_addMethod(flipped, sel_getUid("isFlipped"), (IMP)kr_view_is_flipped, "c@:");
            objc_registerClassPair(flipped);
        }

        // KrSplitter — custom NSView subclass that draws a thin gray
        // bar and tracks mouse drags to update its frame, mirroring the
        // standalone-bar splitter from the Win32 backend.
        Class splitCls = objc_allocateClassPair((Class)objc_getClass("NSView"), "KrSplitter", 0);
        if (splitCls) {
            class_addMethod(splitCls, sel_getUid("mouseDown:"),    (IMP)kr_split_mouseDown_imp,    "v@:@");
            class_addMethod(splitCls, sel_getUid("mouseDragged:"), (IMP)kr_split_mouseDragged_imp, "v@:@");
            class_addMethod(splitCls, sel_getUid("drawRect:"),     (IMP)kr_split_drawRect_imp,     "v@:{CGRect={CGPoint=dd}{CGSize=dd}}");
            class_addMethod(splitCls, sel_getUid("isFlipped"),     (IMP)kr_split_isFlipped_imp,    "c@:");
            objc_registerClassPair(splitCls);
        }

        // KrTreeHelper — single shared object that serves both as
        // NSOutlineView data source and selection-change delegate.
        Class treeCls = objc_allocateClassPair((Class)objc_getClass("NSObject"), "KrTreeHelper", 0);
        if (treeCls) {
            class_addMethod(treeCls, sel_getUid("outlineView:numberOfChildrenOfItem:"),
                            (IMP)kr_tree_num_children_imp,        "q@:@@");
            class_addMethod(treeCls, sel_getUid("outlineView:child:ofItem:"),
                            (IMP)kr_tree_child_imp,               "@@:@q@");
            class_addMethod(treeCls, sel_getUid("outlineView:isItemExpandable:"),
                            (IMP)kr_tree_is_expandable_imp,       "c@:@@");
            class_addMethod(treeCls, sel_getUid("outlineView:objectValueForTableColumn:byItem:"),
                            (IMP)kr_tree_object_value_imp,        "@@:@@@");
            class_addMethod(treeCls, sel_getUid("outlineViewSelectionDidChange:"),
                            (IMP)kr_tree_selection_did_change_imp, "v@:@");
            objc_registerClassPair(treeCls);
        } else {
            treeCls = (Class)objc_getClass("KrTreeHelper");
        }
        g_tree_helper = MSG_O(MSG_O((id)treeCls, sel_getUid("alloc")), sel_getUid("init"));
    }

    char* krGuiInit(void) {
        kr_gui_bootstrap();
        return (char*)"1";
    }

    char* krGuiWindow(char* title, char* w_str, char* h_str) {
        kr_gui_bootstrap();
        int w = atoi(w_str ? w_str : "640");
        int h = atoi(h_str ? h_str : "480");
        if (w <= 0) w = 640;
        if (h <= 0) h = 480;

        unsigned long mask = KR_NS_TITLED | KR_NS_CLOSABLE | KR_NS_MINIATURIZE | KR_NS_RESIZABLE;
        KRRect frame = {{ 100.0, 100.0 }, { (double)w, (double)h }};

        id win = MSG_O((id)objc_getClass("NSWindow"), sel_getUid("alloc"));
        win = ((id(*)(id,SEL,KRRect,unsigned long,unsigned long,signed char))objc_msgSend)(
            win, sel_getUid("initWithContentRect:styleMask:backing:defer:"),
            frame, mask, KR_NS_BACKING_BUF, 0);

        MSG_V_O(win, sel_getUid("setTitle:"), kr_ns_str(title ? title : "Krypton"));

        // Replace the default contentView with our flipped subclass so
        // child-view (x, y) measures from the top-left corner.
        Class flipped = (Class)objc_getClass("KrFlippedView");
        if (flipped) {
            id view = MSG_O((id)flipped, sel_getUid("alloc"));
            KRRect vr = {{0, 0}, {(double)w, (double)h}};
            view = ((id(*)(id,SEL,KRRect))objc_msgSend)(view, sel_getUid("initWithFrame:"), vr);
            MSG_V_O(win, sel_getUid("setContentView:"), view);
            g_content_view = view;
        } else {
            g_content_view = MSG_O(win, sel_getUid("contentView"));
        }

        MSG_V(win, sel_getUid("center"));
        g_main_window = win;
        return kr_handle(win);
    }

    char* krGuiShow(char* hwnd_str) {
        id win = kr_obj_from(hwnd_str);
        if (!win) win = g_main_window;
        if (!win) return (char*)"0";
        MSG_V_O(win, sel_getUid("makeKeyAndOrderFront:"), NULL);
        if (g_app) MSG_V_C(g_app, sel_getUid("activateIgnoringOtherApps:"), 1);
        return (char*)"1";
    }

    // Resolve the parent argument (NSWindow* hex handle) to the
    // contentView the widget should be added to. Falls back to the
    // current main window's contentView so simple programs don't have
    // to thread the handle through.
    static id kr_resolve_container(const char* parent) {
        id host = kr_obj_from(parent);
        if (host) {
            id v = MSG_O(host, sel_getUid("contentView"));
            if (v) return v;
            // Already a view (e.g. dock / stack handle in future).
            return host;
        }
        return g_content_view;
    }

    static int kr_register_cb_slot(void) {
        int id_int = g_next_id++;
        int slot = id_int - 1000;
        if (slot >= 0 && slot < KR_GUI_MAX_CB) g_cb[slot] = NULL;
        return id_int;
    }

    char* krGuiButton(char* parent, char* label, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";

        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id btn = MSG_O((id)objc_getClass("NSButton"), sel_getUid("alloc"));
        btn = ((id(*)(id,SEL,KRRect))objc_msgSend)(btn, sel_getUid("initWithFrame:"), r);
        MSG_V_O(btn, sel_getUid("setTitle:"), kr_ns_str(label ? label : ""));
        MSG_V_L(btn, sel_getUid("setBezelStyle:"), 1);   // NSBezelStyleRounded
        MSG_V_O(btn, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(btn, sel_getUid("setAction:"), sel_getUid("krAction:"));

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(btn, id_int);
        MSG_V_O(container, sel_getUid("addSubview:"), btn);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    static id kr_make_text_field(id container, KRRect r, const char* text, int editable) {
        id tf = MSG_O((id)objc_getClass("NSTextField"), sel_getUid("alloc"));
        tf = ((id(*)(id,SEL,KRRect))objc_msgSend)(tf, sel_getUid("initWithFrame:"), r);
        MSG_V_O(tf, sel_getUid("setStringValue:"), kr_ns_str(text ? text : ""));
        if (!editable) {
            // Label style: no border, no background, no editing.
            MSG_V_C(tf, sel_getUid("setEditable:"),        0);
            MSG_V_C(tf, sel_getUid("setBezeled:"),         0);
            MSG_V_C(tf, sel_getUid("setDrawsBackground:"), 0);
            MSG_V_C(tf, sel_getUid("setSelectable:"),      0);
        } else {
            MSG_V_C(tf, sel_getUid("setEditable:"), 1);
            MSG_V_C(tf, sel_getUid("setBezeled:"),  1);
        }
        MSG_V_O(container, sel_getUid("addSubview:"), tf);
        return tf;
    }

    char* krGuiLabel(char* parent, char* text, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};
        return kr_handle(kr_make_text_field(container, r, text, 0));
    }

    char* krGuiTextInput(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};
        return kr_handle(kr_make_text_field(container, r, "", 1));
    }

    // Resolve a control handle that may be either a hex pointer (label /
    // text-field NSObject*) or a decimal control id (button — registered
    // via setTag:). Decimal lookup walks the contentView's subviews.
    static id kr_resolve_control(const char* s) {
        if (!s || !*s) return NULL;
        if (s[0] == '0' && s[1] == 'x') return kr_obj_from(s);
        long want = atol(s);
        if (!g_content_view) return NULL;
        id arr = MSG_O(g_content_view, sel_getUid("subviews"));
        if (!arr) return NULL;
        long n = MSG_L(arr, sel_getUid("count"));
        for (long i = 0; i < n; i++) {
            id sub = ((id(*)(id,SEL,long))objc_msgSend)(arr, sel_getUid("objectAtIndex:"), i);
            long tag = kr_get_widget_tag(sub);
            if (tag == want) return sub;
        }
        return NULL;
    }

    // For multi-line text areas the user holds an NSScrollView handle;
    // the actual text lives on its document view (an NSTextView). All
    // text reads/writes thread through this resolver.
    static id kr_text_target(id ctl) {
        if (!ctl) return NULL;
        Class scrollCls = (Class)objc_getClass("NSScrollView");
        if (scrollCls && ((signed char(*)(id,SEL,Class))objc_msgSend)(
                ctl, sel_getUid("isKindOfClass:"), scrollCls)) {
            id doc = MSG_O(ctl, sel_getUid("documentView"));
            if (doc) return doc;
        }
        return ctl;
    }

    static int kr_is_textview(id obj) {
        if (!obj) return 0;
        Class tvCls = (Class)objc_getClass("NSTextView");
        if (!tvCls) return 0;
        return ((signed char(*)(id,SEL,Class))objc_msgSend)(
                obj, sel_getUid("isKindOfClass:"), tvCls) != 0;
    }

    char* krGuiSetText(char* hwnd_str, char* text) {
        id ctl = kr_text_target(kr_resolve_control(hwnd_str));
        if (!ctl) return (char*)"0";
        id ns = kr_ns_str(text ? text : "");
        if (kr_is_textview(ctl)) {
            // NSTextView uses -setString:, not -setStringValue:.
            MSG_V_O(ctl, sel_getUid("setString:"), ns);
            return (char*)"1";
        }
        SEL setStr = sel_getUid("setStringValue:");
        if (((signed char(*)(id,SEL,SEL))objc_msgSend)(
                ctl, sel_getUid("respondsToSelector:"), setStr)) {
            MSG_V_O(ctl, setStr, ns);
            return (char*)"1";
        }
        // Buttons store their visible text under -setTitle:.
        MSG_V_O(ctl, sel_getUid("setTitle:"), ns);
        return (char*)"1";
    }

    char* krGuiGetText(char* hwnd_str) {
        id ctl = kr_text_target(kr_resolve_control(hwnd_str));
        if (!ctl) return (char*)"";
        if (kr_is_textview(ctl)) {
            return kr_ns_to_c(MSG_O(ctl, sel_getUid("string")));
        }
        SEL getStr = sel_getUid("stringValue");
        if (((signed char(*)(id,SEL,SEL))objc_msgSend)(
                ctl, sel_getUid("respondsToSelector:"), getStr)) {
            return kr_ns_to_c(MSG_O(ctl, getStr));
        }
        return kr_ns_to_c(MSG_O(ctl, sel_getUid("title")));
    }

    char* krGuiOnClick(char* id_str, char* sinkPtr) {
        int id_int = atoi(id_str ? id_str : "0");
        int slot = id_int - 1000;
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return (char*)"0";
        g_cb[slot] = (kr_gui_cb)sinkPtr;
        return (char*)"1";
    }

    char* krGuiMessageBox(char* title, char* msg) {
        kr_gui_bootstrap();
        id alert = MSG_O((id)objc_getClass("NSAlert"), sel_getUid("alloc"));
        alert = MSG_O(alert, sel_getUid("init"));
        MSG_V_O(alert, sel_getUid("setMessageText:"),     kr_ns_str(title ? title : "Krypton"));
        MSG_V_O(alert, sel_getUid("setInformativeText:"), kr_ns_str(msg   ? msg   : ""));
        ((long(*)(id,SEL))objc_msgSend)(alert, sel_getUid("runModal"));
        return (char*)"1";
    }

    char* krGuiRun(void) {
        if (!g_app) kr_gui_bootstrap();
        if (g_app) MSG_V(g_app, sel_getUid("run"));
        return (char*)"0";
    }

    char* krGuiQuit(void) {
        if (g_app) MSG_V_O(g_app, sel_getUid("terminate:"), NULL);
        return (char*)"1";
    }

    // ──────────────────────────────────────────────────────────────────
    // Round 2 widgets — checkbox, combo, slider, progress, text area,
    // image, file dialogs, listbox, move.
    // ──────────────────────────────────────────────────────────────────

    // ── Checkbox ──────────────────────────────────────────────────
    char* krGuiCheckbox(char* parent, char* label, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id btn = MSG_O((id)objc_getClass("NSButton"), sel_getUid("alloc"));
        btn = ((id(*)(id,SEL,KRRect))objc_msgSend)(btn, sel_getUid("initWithFrame:"), r);
        MSG_V_O(btn, sel_getUid("setTitle:"), kr_ns_str(label ? label : ""));
        MSG_V_L(btn, sel_getUid("setButtonType:"), 3);   // NSButtonTypeSwitch
        MSG_V_O(btn, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(btn, sel_getUid("setAction:"), sel_getUid("krAction:"));

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(btn, id_int);
        MSG_V_O(container, sel_getUid("addSubview:"), btn);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    char* krGuiIsChecked(char* hwnd_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        long state = MSG_L(ctl, sel_getUid("state"));
        return state ? (char*)"1" : (char*)"0";
    }

    char* krGuiSetChecked(char* hwnd_str, char* on_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        int on = atoi(on_str ? on_str : "0");
        MSG_V_L(ctl, sel_getUid("setState:"), on ? 1 : 0);
        return (char*)"1";
    }

    // ── Combo (NSPopUpButton, non-editable) ───────────────────────
    char* krGuiCombo(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id pop = MSG_O((id)objc_getClass("NSPopUpButton"), sel_getUid("alloc"));
        // pullsDown:NO → value-selecting menu (matches Win32 CBS_DROPDOWNLIST).
        pop = ((id(*)(id,SEL,KRRect,signed char))objc_msgSend)(
            pop, sel_getUid("initWithFrame:pullsDown:"), r, 0);

        // Tag + target/action so `guiOnChange(combo, fn)` works the
        // same way it does for sliders (action fires on item pick).
        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(pop, id_int);
        MSG_V_O(pop, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(pop, sel_getUid("setAction:"), sel_getUid("krAction:"));

        MSG_V_O(container, sel_getUid("addSubview:"), pop);
        return kr_handle(pop);
    }

    char* krGuiComboAdd(char* hwnd_str, char* item) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        MSG_V_O(ctl, sel_getUid("addItemWithTitle:"), kr_ns_str(item ? item : ""));
        return (char*)"1";
    }

    char* krGuiComboClear(char* hwnd_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        MSG_V(ctl, sel_getUid("removeAllItems"));
        return (char*)"1";
    }

    char* krGuiComboSelected(char* hwnd_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"";
        id ns = MSG_O(ctl, sel_getUid("titleOfSelectedItem"));
        if (!ns) return (char*)"";
        return kr_ns_to_c(ns);
    }

    char* krGuiComboSet(char* hwnd_str, char* idx_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        long idx = atol(idx_str ? idx_str : "0");
        MSG_V_L(ctl, sel_getUid("selectItemAtIndex:"), idx);
        return (char*)"1";
    }

    // ── Slider (NSSlider, horizontal) ─────────────────────────────
    char* krGuiSlider(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id sl = MSG_O((id)objc_getClass("NSSlider"), sel_getUid("alloc"));
        sl = ((id(*)(id,SEL,KRRect))objc_msgSend)(sl, sel_getUid("initWithFrame:"), r);
        ((void(*)(id,SEL,double))objc_msgSend)(sl, sel_getUid("setMinValue:"),    0.0);
        ((void(*)(id,SEL,double))objc_msgSend)(sl, sel_getUid("setMaxValue:"),    100.0);
        ((void(*)(id,SEL,double))objc_msgSend)(sl, sel_getUid("setDoubleValue:"), 0.0);
        MSG_V_O(sl, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(sl, sel_getUid("setAction:"), sel_getUid("krAction:"));

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(sl, id_int);
        MSG_V_O(container, sel_getUid("addSubview:"), sl);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    char* krGuiSliderRange(char* sl_str, char* lo_str, char* hi_str) {
        id ctl = kr_resolve_control(sl_str);
        if (!ctl) return (char*)"0";
        ((void(*)(id,SEL,double))objc_msgSend)(ctl, sel_getUid("setMinValue:"),
            atof(lo_str ? lo_str : "0"));
        ((void(*)(id,SEL,double))objc_msgSend)(ctl, sel_getUid("setMaxValue:"),
            atof(hi_str ? hi_str : "100"));
        return (char*)"1";
    }

    char* krGuiSliderSet(char* sl_str, char* v_str) {
        id ctl = kr_resolve_control(sl_str);
        if (!ctl) return (char*)"0";
        ((void(*)(id,SEL,double))objc_msgSend)(ctl, sel_getUid("setDoubleValue:"),
            atof(v_str ? v_str : "0"));
        return (char*)"1";
    }

    char* krGuiSliderValue(char* sl_str) {
        id ctl = kr_resolve_control(sl_str);
        if (!ctl) return (char*)"0";
        double v = ((double(*)(id,SEL))objc_msgSend)(ctl, sel_getUid("doubleValue"));
        char buf[32];
        snprintf(buf, sizeof(buf), "%d", (int)v);
        return kr_gui_dup(buf);
    }

    // ── Progress bar (NSProgressIndicator, bar style) ─────────────
    char* krGuiProgress(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id pi = MSG_O((id)objc_getClass("NSProgressIndicator"), sel_getUid("alloc"));
        pi = ((id(*)(id,SEL,KRRect))objc_msgSend)(pi, sel_getUid("initWithFrame:"), r);
        MSG_V_L(pi, sel_getUid("setStyle:"),         0);   // NSProgressIndicatorStyleBar
        MSG_V_C(pi, sel_getUid("setIndeterminate:"), 0);
        ((void(*)(id,SEL,double))objc_msgSend)(pi, sel_getUid("setMinValue:"),   0.0);
        ((void(*)(id,SEL,double))objc_msgSend)(pi, sel_getUid("setMaxValue:"), 100.0);
        MSG_V_O(container, sel_getUid("addSubview:"), pi);
        return kr_handle(pi);
    }

    char* krGuiProgressSet(char* hwnd_str, char* pct_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        double v = atof(pct_str ? pct_str : "0");
        if (v < 0)   v = 0;
        if (v > 100) v = 100;
        ((void(*)(id,SEL,double))objc_msgSend)(ctl, sel_getUid("setDoubleValue:"), v);
        return (char*)"1";
    }

    // ── Text area (NSTextView in NSScrollView) ────────────────────
    //
    // The Krypton-visible handle is the NSScrollView so guiMove acts on
    // the scrollable container; krGuiSetText / krGuiGetText forward
    // through documentView via kr_text_target.
    char* krGuiTextArea(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id sv = MSG_O((id)objc_getClass("NSScrollView"), sel_getUid("alloc"));
        sv = ((id(*)(id,SEL,KRRect))objc_msgSend)(sv, sel_getUid("initWithFrame:"), r);
        MSG_V_C(sv, sel_getUid("setHasVerticalScroller:"),   1);
        MSG_V_C(sv, sel_getUid("setHasHorizontalScroller:"), 0);
        MSG_V_L(sv, sel_getUid("setBorderType:"),            2);   // NSBezelBorder

        id tv = MSG_O((id)objc_getClass("NSTextView"), sel_getUid("alloc"));
        KRRect tvr = {{ 0, 0 }, { r.size.width, r.size.height }};
        tv = ((id(*)(id,SEL,KRRect))objc_msgSend)(tv, sel_getUid("initWithFrame:"), tvr);
        MSG_V_C(tv, sel_getUid("setEditable:"),   1);
        MSG_V_C(tv, sel_getUid("setSelectable:"), 1);
        MSG_V_C(tv, sel_getUid("setRichText:"),   0);

        MSG_V_O(sv, sel_getUid("setDocumentView:"), tv);
        MSG_V_O(container, sel_getUid("addSubview:"), sv);
        return kr_handle(sv);
    }

    // ── Move (relocate / resize any view) ─────────────────────────
    char* krGuiMove(char* hwnd_str, char* x_str, char* y_str, char* w_str, char* h_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};
        ((void(*)(id,SEL,KRRect))objc_msgSend)(ctl, sel_getUid("setFrame:"), r);
        return (char*)"1";
    }

    // ── Image (NSImageView) ───────────────────────────────────────
    static id kr_load_ns_image(const char* path) {
        if (!path || !*path) return NULL;
        id ns_path = kr_ns_str(path);
        id img = MSG_O((id)objc_getClass("NSImage"), sel_getUid("alloc"));
        img = MSG_O_O(img, sel_getUid("initWithContentsOfFile:"), ns_path);
        return img;
    }

    char* krGuiImage(char* parent, char* path, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id iv = MSG_O((id)objc_getClass("NSImageView"), sel_getUid("alloc"));
        iv = ((id(*)(id,SEL,KRRect))objc_msgSend)(iv, sel_getUid("initWithFrame:"), r);
        MSG_V_L(iv, sel_getUid("setImageScaling:"), 0);   // NSImageScaleProportionallyDown
        id img = kr_load_ns_image(path);
        if (img) MSG_V_O(iv, sel_getUid("setImage:"), img);
        MSG_V_O(container, sel_getUid("addSubview:"), iv);
        return kr_handle(iv);
    }

    char* krGuiImageSet(char* hwnd_str, char* path) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"0";
        id img = kr_load_ns_image(path);
        if (!img) return (char*)"0";
        MSG_V_O(ctl, sel_getUid("setImage:"), img);
        return (char*)"1";
    }

    // ── File dialogs (NSOpenPanel / NSSavePanel) ──────────────────
    //
    // The Win32 contract for filterCsv accepts either a flat list like
    // "*.txt,*.md" or labelled groups like "Text:*.txt;*.md". Cocoa
    // wants bare extensions, so we strip "*." / leading "." and hand
    // an NSArray of extension strings to -setAllowedFileTypes:. (That
    // selector is deprecated in 10.15+ but still functional; the UTType
    // replacement requires the UniformTypeIdentifiers framework.)
    static id kr_build_filetypes_array(const char* csv) {
        id arr = MSG_O((id)objc_getClass("NSMutableArray"), sel_getUid("array"));
        if (!csv || !*csv) return arr;
        char buf[1024];
        size_t n = strlen(csv);
        if (n >= sizeof(buf)) n = sizeof(buf) - 1;
        memcpy(buf, csv, n);
        buf[n] = 0;
        char* p = buf;
        while (*p) {
            while (*p == ',' || *p == ';' || *p == ' ') p++;
            char* tok = p;
            while (*p && *p != ',' && *p != ';') p++;
            char save = *p;
            *p = 0;
            char* colon = strchr(tok, ':');
            if (colon) tok = colon + 1;
            if      (tok[0] == '*' && tok[1] == '.') tok += 2;
            else if (tok[0] == '*')                  tok += 1;
            if (tok[0] == '.') tok += 1;
            if (*tok) {
                MSG_V_O(arr, sel_getUid("addObject:"), kr_ns_str(tok));
            }
            *p = save;
            if (save) p++;
        }
        return arr;
    }

    char* krGuiOpenFile(char* title, char* filterCsv) {
        kr_gui_bootstrap();
        id panel = MSG_O((id)objc_getClass("NSOpenPanel"), sel_getUid("openPanel"));
        MSG_V_O(panel, sel_getUid("setTitle:"),
                kr_ns_str((title && *title) ? title : "Open File"));
        MSG_V_C(panel, sel_getUid("setCanChooseFiles:"),         1);
        MSG_V_C(panel, sel_getUid("setCanChooseDirectories:"),   0);
        MSG_V_C(panel, sel_getUid("setAllowsMultipleSelection:"),0);
        if (filterCsv && *filterCsv) {
            MSG_V_O(panel, sel_getUid("setAllowedFileTypes:"),
                    kr_build_filetypes_array(filterCsv));
        }
        long ok = ((long(*)(id,SEL))objc_msgSend)(panel, sel_getUid("runModal"));
        if (ok != 1) return (char*)"";   // NSModalResponseOK = 1
        id url = MSG_O(panel, sel_getUid("URL"));
        if (!url) return (char*)"";
        return kr_ns_to_c(MSG_O(url, sel_getUid("path")));
    }

    char* krGuiSaveFile(char* title, char* filterCsv, char* defaultName) {
        kr_gui_bootstrap();
        id panel = MSG_O((id)objc_getClass("NSSavePanel"), sel_getUid("savePanel"));
        MSG_V_O(panel, sel_getUid("setTitle:"),
                kr_ns_str((title && *title) ? title : "Save File"));
        if (defaultName && *defaultName) {
            MSG_V_O(panel, sel_getUid("setNameFieldStringValue:"),
                    kr_ns_str(defaultName));
        }
        if (filterCsv && *filterCsv) {
            MSG_V_O(panel, sel_getUid("setAllowedFileTypes:"),
                    kr_build_filetypes_array(filterCsv));
        }
        long ok = ((long(*)(id,SEL))objc_msgSend)(panel, sel_getUid("runModal"));
        if (ok != 1) return (char*)"";
        id url = MSG_O(panel, sel_getUid("URL"));
        if (!url) return (char*)"";
        return kr_ns_to_c(MSG_O(url, sel_getUid("path")));
    }

    char* krGuiPickFolder(char* title) {
        kr_gui_bootstrap();
        id panel = MSG_O((id)objc_getClass("NSOpenPanel"), sel_getUid("openPanel"));
        MSG_V_O(panel, sel_getUid("setTitle:"),
                kr_ns_str((title && *title) ? title : "Pick a folder"));
        MSG_V_C(panel, sel_getUid("setCanChooseFiles:"),         0);
        MSG_V_C(panel, sel_getUid("setCanChooseDirectories:"),   1);
        MSG_V_C(panel, sel_getUid("setAllowsMultipleSelection:"),0);
        long ok = ((long(*)(id,SEL))objc_msgSend)(panel, sel_getUid("runModal"));
        if (ok != 1) return (char*)"";
        id url = MSG_O(panel, sel_getUid("URL"));
        if (!url) return (char*)"";
        return kr_ns_to_c(MSG_O(url, sel_getUid("path")));
    }

    // ── Listbox (NSScrollView around NSTableView) ─────────────────
    //
    // Cocoa lists are data-source-driven, so we attach an NSMutableArray
    // to each NSTableView via objc_setAssociatedObject and feed it back
    // through one shared data source object that responds to
    // -numberOfRowsInTableView: and -tableView:objectValueForTableColumn:row:.
    // The Krypton-visible handle is the NSScrollView (so guiMove acts on
    // the scrollable container, not just the inner table).

    static char kr_listbox_array_key;   // sentinel used as objc associated-object key

    static long kr_lb_num_rows(id self, SEL _cmd, id tv) {
        (void)self; (void)_cmd;
        id arr = (id)objc_getAssociatedObject(tv, &kr_listbox_array_key);
        if (!arr) return 0;
        return MSG_L(arr, sel_getUid("count"));
    }

    static id kr_lb_obj_for_row(id self, SEL _cmd, id tv, id col, long row) {
        (void)self; (void)_cmd; (void)col;
        id arr = (id)objc_getAssociatedObject(tv, &kr_listbox_array_key);
        if (!arr) return NULL;
        return ((id(*)(id,SEL,long))objc_msgSend)(arr, sel_getUid("objectAtIndex:"), row);
    }

    static id g_listbox_ds = NULL;

    static void kr_listbox_init(void) {
        if (g_listbox_ds) return;
        Class dsCls = objc_allocateClassPair((Class)objc_getClass("NSObject"), "KrListDS", 0);
        if (dsCls) {
            class_addMethod(dsCls, sel_getUid("numberOfRowsInTableView:"),
                            (IMP)kr_lb_num_rows,    "q@:@");
            class_addMethod(dsCls, sel_getUid("tableView:objectValueForTableColumn:row:"),
                            (IMP)kr_lb_obj_for_row, "@@:@@q");
            objc_registerClassPair(dsCls);
        } else {
            dsCls = (Class)objc_getClass("KrListDS");
        }
        g_listbox_ds = MSG_O(MSG_O((id)dsCls, sel_getUid("alloc")), sel_getUid("init"));
    }

    // Resolve a listbox handle (NSScrollView pointer) to its inner
    // NSTableView. Returns NULL if the handle isn't actually a list.
    static id kr_lb_table(const char* h) {
        id sv = kr_obj_from(h);
        if (!sv) return NULL;
        Class scrollCls = (Class)objc_getClass("NSScrollView");
        if (scrollCls && !((signed char(*)(id,SEL,Class))objc_msgSend)(
                sv, sel_getUid("isKindOfClass:"), scrollCls)) return NULL;
        return MSG_O(sv, sel_getUid("documentView"));
    }

    char* krGuiListbox(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        kr_listbox_init();
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id sv = MSG_O((id)objc_getClass("NSScrollView"), sel_getUid("alloc"));
        sv = ((id(*)(id,SEL,KRRect))objc_msgSend)(sv, sel_getUid("initWithFrame:"), r);
        MSG_V_C(sv, sel_getUid("setHasVerticalScroller:"), 1);
        MSG_V_L(sv, sel_getUid("setBorderType:"),          2);

        id tv = MSG_O((id)objc_getClass("NSTableView"), sel_getUid("alloc"));
        KRRect tvr = {{ 0, 0 }, { r.size.width, r.size.height }};
        tv = ((id(*)(id,SEL,KRRect))objc_msgSend)(tv, sel_getUid("initWithFrame:"), tvr);
        MSG_V_O(tv, sel_getUid("setHeaderView:"), NULL);   // hide header (single-column list)
        MSG_V_C(tv, sel_getUid("setAllowsMultipleSelection:"), 0);

        id col = MSG_O((id)objc_getClass("NSTableColumn"), sel_getUid("alloc"));
        col = MSG_O_O(col, sel_getUid("initWithIdentifier:"), kr_ns_str("c0"));
        ((void(*)(id,SEL,double))objc_msgSend)(col, sel_getUid("setWidth:"),
                                               r.size.width - 2.0);
        MSG_V_O(tv, sel_getUid("addTableColumn:"), col);

        // Backing array, retained via the table view's associated objects.
        id arr = MSG_O((id)objc_getClass("NSMutableArray"), sel_getUid("array"));
        objc_setAssociatedObject(tv, &kr_listbox_array_key, arr, 1);  // OBJC_ASSOCIATION_RETAIN_NONATOMIC
        MSG_V_O(tv, sel_getUid("setDataSource:"), g_listbox_ds);

        MSG_V_O(sv, sel_getUid("setDocumentView:"), tv);
        MSG_V_O(container, sel_getUid("addSubview:"), sv);
        return kr_handle(sv);
    }

    char* krGuiListAdd(char* hwnd_str, char* item) {
        id tv = kr_lb_table(hwnd_str);
        if (!tv) return (char*)"0";
        id arr = (id)objc_getAssociatedObject(tv, &kr_listbox_array_key);
        if (!arr) return (char*)"0";
        MSG_V_O(arr, sel_getUid("addObject:"), kr_ns_str(item ? item : ""));
        MSG_V(tv, sel_getUid("reloadData"));
        return (char*)"1";
    }

    char* krGuiListClear(char* hwnd_str) {
        id tv = kr_lb_table(hwnd_str);
        if (!tv) return (char*)"0";
        id arr = (id)objc_getAssociatedObject(tv, &kr_listbox_array_key);
        if (!arr) return (char*)"0";
        MSG_V(arr, sel_getUid("removeAllObjects"));
        MSG_V(tv, sel_getUid("reloadData"));
        return (char*)"1";
    }

    char* krGuiListSelected(char* hwnd_str) {
        id tv = kr_lb_table(hwnd_str);
        if (!tv) return (char*)"";
        long row = MSG_L(tv, sel_getUid("selectedRow"));
        if (row < 0) return (char*)"";
        id arr = (id)objc_getAssociatedObject(tv, &kr_listbox_array_key);
        if (!arr) return (char*)"";
        long n = MSG_L(arr, sel_getUid("count"));
        if (row >= n) return (char*)"";
        id ns = ((id(*)(id,SEL,long))objc_msgSend)(arr, sel_getUid("objectAtIndex:"), row);
        return kr_ns_to_c(ns);
    }

    // ──────────────────────────────────────────────────────────────────
    // Round 4 widgets — spinbox, stack helpers, splitter.
    // ──────────────────────────────────────────────────────────────────

    // ── Spinbox (NSStepper + NSTextField composite) ──────────────
    //
    // Cocoa's NSStepper is just the up/down arrows; the visible value
    // lives in a paired NSTextField. We add both as siblings, store
    // each on the other via objc_setAssociatedObject, and route the
    // stepper's action through krSpinAction: which mirrors the integer
    // value into the textfield and fires user callbacks.
    //
    // The user-visible handle is the textfield's pointer (matches the
    // Win32 EDIT-id convention — guiSetText / guiGetText already work
    // on text fields). guiSpinboxRange / Set / Value forward through
    // the textfield's associated stepper.

    char* krGuiSpinbox(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        int x = atoi(x_str), y = atoi(y_str);
        int w = atoi(w_str), h = atoi(h_str);
        const int stepper_w = 19;        // standard NSStepper width
        const int gap       = 2;

        KRRect tfr = {{ (double)x,                              (double)y },
                      { (double)(w - stepper_w - gap),          (double)h }};
        KRRect str = {{ (double)(x + w - stepper_w),            (double)y },
                      { (double)stepper_w,                      (double)h }};

        id tf = MSG_O((id)objc_getClass("NSTextField"), sel_getUid("alloc"));
        tf = ((id(*)(id,SEL,KRRect))objc_msgSend)(tf, sel_getUid("initWithFrame:"), tfr);
        MSG_V_C(tf, sel_getUid("setEditable:"), 1);
        MSG_V_C(tf, sel_getUid("setBezeled:"),  1);
        MSG_V_O(tf, sel_getUid("setStringValue:"), kr_ns_str("0"));
        MSG_V_L(tf, sel_getUid("setAlignment:"), 1);   // NSTextAlignmentRight

        id st = MSG_O((id)objc_getClass("NSStepper"), sel_getUid("alloc"));
        st = ((id(*)(id,SEL,KRRect))objc_msgSend)(st, sel_getUid("initWithFrame:"), str);
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setMinValue:"),    0.0);
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setMaxValue:"),    100.0);
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setIncrement:"),   1.0);
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setDoubleValue:"), 0.0);
        MSG_V_C(st, sel_getUid("setValueWraps:"), 0);
        MSG_V_O(st, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(st, sel_getUid("setAction:"), sel_getUid("krSpinAction:"));

        // Same slot for both halves so guiOnChange works whether the
        // user passes the textfield handle or the stepper handle.
        int slot_id = kr_register_cb_slot();
        kr_set_widget_tag(st, slot_id);
        kr_set_widget_tag(tf, slot_id);

        objc_setAssociatedObject(st, &kr_spin_partner_key, tf, 1); // OBJC_ASSOCIATION_RETAIN_NONATOMIC
        objc_setAssociatedObject(tf, &kr_spin_partner_key, st, 1);

        MSG_V_O(container, sel_getUid("addSubview:"), tf);
        MSG_V_O(container, sel_getUid("addSubview:"), st);
        return kr_handle(tf);
    }

    char* krGuiSpinboxRange(char* sb_str, char* lo_str, char* hi_str) {
        id tf = kr_obj_from(sb_str);
        if (!tf) return (char*)"0";
        id st = (id)objc_getAssociatedObject(tf, &kr_spin_partner_key);
        if (!st) return (char*)"0";
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setMinValue:"),
            atof(lo_str ? lo_str : "0"));
        ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setMaxValue:"),
            atof(hi_str ? hi_str : "100"));
        return (char*)"1";
    }

    char* krGuiSpinboxSet(char* sb_str, char* v_str) {
        id tf = kr_obj_from(sb_str);
        if (!tf) return (char*)"0";
        id st = (id)objc_getAssociatedObject(tf, &kr_spin_partner_key);
        if (st) ((void(*)(id,SEL,double))objc_msgSend)(st, sel_getUid("setDoubleValue:"),
                                                       atof(v_str ? v_str : "0"));
        MSG_V_O(tf, sel_getUid("setStringValue:"), kr_ns_str(v_str ? v_str : "0"));
        return (char*)"1";
    }

    char* krGuiSpinboxValue(char* sb_str) {
        id tf = kr_obj_from(sb_str);
        if (!tf) return (char*)"0";
        return kr_ns_to_c(MSG_O(tf, sel_getUid("stringValue")));
    }

    // ── Layout stacks (pure C state) ─────────────────────────────
    //
    // Mirrors the Win32 stack helpers. A "stack" is just a layout
    // cursor — parent, origin, cross-axis size, gap, current cursor.
    // Each VNext / HNext returns the next coord and advances. No Cocoa
    // calls — this is pure C state with the parent stored as a generic
    // pointer (the caller's window handle).
    typedef struct {
        id   parent;       // NSWindow* the user passed in
        int  x, y;
        int  cross;        // width (V) or height (H)
        int  gap;
        int  cursor;       // next y (V) or next x (H)
        int  orient;       // 0 = V, 1 = H
    } kr_gui_stack;

    static kr_gui_stack* kr_stack_resolve(const char* h) {
        if (!h || h[0] != '0' || h[1] != 'x') return NULL;
        void* p = NULL;
        if (sscanf(h, "%p", &p) != 1) return NULL;
        return (kr_gui_stack*)p;
    }

    static char* kr_stack_alloc(id parent, int x, int y, int cross, int gap, int orient) {
        kr_gui_stack* s = (kr_gui_stack*)malloc(sizeof(*s));
        if (!s) return (char*)"0";
        s->parent = parent;
        s->x      = x;
        s->y      = y;
        s->cross  = cross;
        s->gap    = gap;
        s->cursor = (orient == 0) ? y : x;
        s->orient = orient;
        char buf[32];
        snprintf(buf, sizeof(buf), "%p", (void*)s);
        return kr_gui_dup(buf);
    }

    char* krGuiVStack(char* parent_str, char* xs, char* ys, char* ws, char* gs) {
        id parent = kr_obj_from(parent_str);
        if (!parent) parent = g_main_window;
        return kr_stack_alloc(parent, atoi(xs), atoi(ys), atoi(ws), atoi(gs), 0);
    }

    char* krGuiHStack(char* parent_str, char* xs, char* ys, char* hs, char* gs) {
        id parent = kr_obj_from(parent_str);
        if (!parent) parent = g_main_window;
        return kr_stack_alloc(parent, atoi(xs), atoi(ys), atoi(hs), atoi(gs), 1);
    }

    char* krGuiVNext(char* stack_str, char* size_str) {
        kr_gui_stack* s = kr_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        int cur = s->cursor;
        s->cursor += atoi(size_str ? size_str : "0") + s->gap;
        char buf[16]; snprintf(buf, sizeof(buf), "%d", cur);
        return kr_gui_dup(buf);
    }

    char* krGuiHNext(char* stack_str, char* size_str) {
        return krGuiVNext(stack_str, size_str);   // symmetric over the orient axis
    }

    char* krGuiStackParent(char* stack_str) {
        kr_gui_stack* s = kr_stack_resolve(stack_str);
        if (!s || !s->parent) return (char*)"0";
        return kr_handle(s->parent);
    }

    static char* kr_stack_int_field(const char* stack_str, int v) {
        kr_gui_stack* s = kr_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", v);
        return kr_gui_dup(buf);
    }

    char* krGuiStackX(char* s)   { kr_gui_stack* k = kr_stack_resolve(s); return k ? kr_stack_int_field(s, k->x)      : (char*)"0"; }
    char* krGuiStackY(char* s)   { kr_gui_stack* k = kr_stack_resolve(s); return k ? kr_stack_int_field(s, k->y)      : (char*)"0"; }
    char* krGuiStackW(char* s)   { kr_gui_stack* k = kr_stack_resolve(s); return k ? kr_stack_int_field(s, k->cross)  : (char*)"0"; }
    char* krGuiStackH(char* s)   { return krGuiStackW(s); }
    char* krGuiStackGap(char* s) { kr_gui_stack* k = kr_stack_resolve(s); return k ? kr_stack_int_field(s, k->gap)    : (char*)"0"; }

    char* krGuiStackGapAdd(char* stack_str, char* px_str) {
        kr_gui_stack* s = kr_stack_resolve(stack_str);
        if (!s) return (char*)"0";
        s->cursor += atoi(px_str ? px_str : "0");
        return (char*)"1";
    }

    // ── Splitter (custom NSView with mouse tracking) ─────────────
    //
    // Matches the Win32 standalone-bar contract: a thin draggable bar
    // that the user moves to resize sibling panels. Position changes
    // fire the registered onChange callback; guiSplitterPos returns the
    // current top-edge (horizontal bar) or left-edge (vertical bar).

    char* krGuiSplitter(char* parent, char* x_str, char* y_str, char* w_str, char* h_str,
                        char* orient_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        int orient = 0;   // 0 = horizontal bar (user drags vertically)
        if (orient_str && (orient_str[0] == 'v' || orient_str[0] == 'V')) orient = 1;

        int x = atoi(x_str), y = atoi(y_str);
        int w = atoi(w_str), h = atoi(h_str);
        KRRect r = {{ (double)x, (double)y }, { (double)w, (double)h }};

        Class splitCls = (Class)objc_getClass("KrSplitter");
        if (!splitCls) return (char*)"";
        id view = MSG_O((id)splitCls, sel_getUid("alloc"));
        view = ((id(*)(id,SEL,KRRect))objc_msgSend)(view, sel_getUid("initWithFrame:"), r);

        kr_split_state* s = (kr_split_state*)malloc(sizeof(*s));
        s->orient           = orient;
        s->pos              = (orient == 0) ? y : x;
        s->drag_start_mouse = 0.0;
        s->drag_start_pos   = s->pos;
        // OBJC_ASSOCIATION_ASSIGN (= 0) so the runtime treats it as an
        // opaque void* — it's a malloc'd struct, not an Objective-C
        // object, so we don't want retain/release semantics.
        objc_setAssociatedObject(view, &kr_split_state_key, (id)s, 0);

        int slot_id = kr_register_cb_slot();
        kr_set_widget_tag(view, slot_id);

        MSG_V_O(container, sel_getUid("addSubview:"), view);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", slot_id);
        return kr_gui_dup(buf);
    }

    char* krGuiSplitterPos(char* sp_str) {
        id ctl = kr_resolve_control(sp_str);
        if (!ctl) return (char*)"0";
        kr_split_state* s = (kr_split_state*)objc_getAssociatedObject(ctl, &kr_split_state_key);
        if (!s) return (char*)"0";
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", s->pos);
        return kr_gui_dup(buf);
    }

    // ──────────────────────────────────────────────────────────────────
    // Stubs for the remaining surface — tree, status bar, toolbar,
    // dock manager, color picker, scrollbar. Each returns an empty
    // handle / "0" so existing programs link and run.
    // ──────────────────────────────────────────────────────────────────

    #define KR_STUB_S(name, ...) char* name(__VA_ARGS__) { return (char*)""; }
    #define KR_STUB_0(name, ...) char* name(__VA_ARGS__) { return (char*)"0"; }

    // ── Universal change-event hook ─────────────────────────────
    //
    // Decimal id (slider, tabs, menu items) or hex pointer (combo,
    // date picker — anything we wired with setTag:) both work; the
    // hex form looks up the widget's tag and resolves to the same slot.
    char* krGuiOnChange(char* id_str, char* sinkPtr) {
        int slot = -1;
        if (id_str && id_str[0] == '0' && id_str[1] == 'x') {
            id ctl = kr_obj_from(id_str);
            if (ctl) {
                long tag = kr_get_widget_tag(ctl);
                if (tag >= 1000) slot = (int)tag - 1000;
            }
        } else {
            slot = atoi(id_str ? id_str : "0") - 1000;
        }
        if (slot < 0 || slot >= KR_GUI_MAX_CB) return (char*)"0";
        g_change_cb[slot] = (kr_gui_cb)sinkPtr;
        return (char*)"1";
    }

    // ── Menus (NSMenu / NSMenuItem in the application main menu) ─
    //
    // macOS shows menus in the global menu bar at the top of the
    // screen, not attached to a specific window. We lazily allocate
    // an NSMenu, install it via [NSApp setMainMenu:], and seed it
    // with an "App" placeholder containing a system Quit item so the
    // bar renders correctly.

    char* krGuiMenuBegin(char* window_str) {
        (void)window_str;
        kr_gui_bootstrap();
        if (g_menu_bar) return kr_handle(g_menu_bar);

        g_menu_bar = MSG_O((id)objc_getClass("NSMenu"), sel_getUid("alloc"));
        g_menu_bar = MSG_O_O(g_menu_bar, sel_getUid("initWithTitle:"), kr_ns_str(""));

        // Without a leading app menu, the user's first menu becomes
        // the bold app menu — visually wrong. Seed an empty one with
        // a Quit item that uses the standard -terminate: selector so
        // ⌘Q works without us wiring anything.
        id app_item = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        app_item = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            app_item, sel_getUid("initWithTitle:action:keyEquivalent:"),
            kr_ns_str(""), NULL, kr_ns_str(""));

        id app_menu = MSG_O((id)objc_getClass("NSMenu"), sel_getUid("alloc"));
        app_menu = MSG_O_O(app_menu, sel_getUid("initWithTitle:"), kr_ns_str(""));

        id quit = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        quit = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            quit, sel_getUid("initWithTitle:action:keyEquivalent:"),
            kr_ns_str("Quit"), sel_getUid("terminate:"), kr_ns_str("q"));
        MSG_V_O(quit, sel_getUid("setTarget:"), g_app);
        MSG_V_O(app_menu, sel_getUid("addItem:"), quit);

        MSG_V_O(app_item, sel_getUid("setSubmenu:"), app_menu);
        MSG_V_O(g_menu_bar, sel_getUid("addItem:"), app_item);

        MSG_V_O(g_app, sel_getUid("setMainMenu:"), g_menu_bar);
        return kr_handle(g_menu_bar);
    }

    char* krGuiMenu(char* menubar_str, char* label) {
        (void)menubar_str;
        if (!g_menu_bar) krGuiMenuBegin(NULL);
        id title = kr_ns_str(label ? label : "");
        id top = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        top = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            top, sel_getUid("initWithTitle:action:keyEquivalent:"),
            title, NULL, kr_ns_str(""));

        id submenu = MSG_O((id)objc_getClass("NSMenu"), sel_getUid("alloc"));
        submenu = MSG_O_O(submenu, sel_getUid("initWithTitle:"), title);

        MSG_V_O(top, sel_getUid("setSubmenu:"), submenu);
        MSG_V_O(g_menu_bar, sel_getUid("addItem:"), top);
        return kr_handle(submenu);
    }

    char* krGuiMenuItem(char* submenu_str, char* label) {
        id submenu = kr_obj_from(submenu_str);
        if (!submenu) return (char*)"0";

        int id_int = kr_register_cb_slot();
        id item = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        item = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            item, sel_getUid("initWithTitle:action:keyEquivalent:"),
            kr_ns_str(label ? label : ""),
            sel_getUid("krAction:"),
            kr_ns_str(""));
        MSG_V_O(item, sel_getUid("setTarget:"), g_target);
        kr_set_widget_tag(item, id_int);
        MSG_V_O(submenu, sel_getUid("addItem:"), item);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    char* krGuiMenuSeparator(char* submenu_str) {
        id submenu = kr_obj_from(submenu_str);
        if (!submenu) return (char*)"0";
        id sep = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("separatorItem"));
        MSG_V_O(submenu, sel_getUid("addItem:"), sep);
        return (char*)"1";
    }

    // Legacy flat-item API — adds a clickable top-level entry to the
    // menu bar. macOS top-level menus must own a submenu, so we wrap
    // the action in a single-item dropdown and surface that as the
    // visible click target. Functionally indistinguishable to user
    // code; visually shows label → label in the menu.
    char* krGuiMenuAdd(char* menubar_str, char* label) {
        (void)menubar_str;
        if (!g_menu_bar) krGuiMenuBegin(NULL);
        int id_int = kr_register_cb_slot();
        id title = kr_ns_str(label ? label : "");

        id top = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        top = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            top, sel_getUid("initWithTitle:action:keyEquivalent:"),
            title, NULL, kr_ns_str(""));

        id submenu = MSG_O((id)objc_getClass("NSMenu"), sel_getUid("alloc"));
        submenu = MSG_O_O(submenu, sel_getUid("initWithTitle:"), title);

        id child = MSG_O((id)objc_getClass("NSMenuItem"), sel_getUid("alloc"));
        child = ((id(*)(id,SEL,id,SEL,id))objc_msgSend)(
            child, sel_getUid("initWithTitle:action:keyEquivalent:"),
            title, sel_getUid("krAction:"), kr_ns_str(""));
        MSG_V_O(child, sel_getUid("setTarget:"), g_target);
        kr_set_widget_tag(child, id_int);
        MSG_V_O(submenu, sel_getUid("addItem:"), child);

        MSG_V_O(top, sel_getUid("setSubmenu:"), submenu);
        MSG_V_O(g_menu_bar, sel_getUid("addItem:"), top);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    // ── Tabs (NSTabView with delegate-driven change events) ──────
    char* krGuiTabs(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id tabs = MSG_O((id)objc_getClass("NSTabView"), sel_getUid("alloc"));
        tabs = ((id(*)(id,SEL,KRRect))objc_msgSend)(tabs, sel_getUid("initWithFrame:"), r);

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(tabs, id_int);
        if (g_tab_delegate) MSG_V_O(tabs, sel_getUid("setDelegate:"), g_tab_delegate);
        MSG_V_O(container, sel_getUid("addSubview:"), tabs);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    char* krGuiTabAdd(char* tabs_str, char* label) {
        id tabs = kr_resolve_control(tabs_str);
        if (!tabs) return (char*)"-1";
        id title = kr_ns_str(label ? label : "");
        id item  = MSG_O((id)objc_getClass("NSTabViewItem"), sel_getUid("alloc"));
        item = MSG_O_O(item, sel_getUid("initWithIdentifier:"), title);
        MSG_V_O(item, sel_getUid("setLabel:"), title);
        MSG_V_O(tabs, sel_getUid("addTabViewItem:"), item);

        long n = MSG_L(tabs, sel_getUid("numberOfTabViewItems"));
        char buf[16];
        snprintf(buf, sizeof(buf), "%ld", n - 1);
        return kr_gui_dup(buf);
    }

    char* krGuiTabSelected(char* tabs_str) {
        id tabs = kr_resolve_control(tabs_str);
        if (!tabs) return (char*)"-1";
        id sel_item = MSG_O(tabs, sel_getUid("selectedTabViewItem"));
        if (!sel_item) return (char*)"-1";
        long idx = ((long(*)(id,SEL,id))objc_msgSend)(
            tabs, sel_getUid("indexOfTabViewItem:"), sel_item);
        char buf[16];
        snprintf(buf, sizeof(buf), "%ld", idx);
        return kr_gui_dup(buf);
    }

    // ── Date picker (NSDatePicker, textual style + stepper) ──────
    char* krGuiDatePicker(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id dp = MSG_O((id)objc_getClass("NSDatePicker"), sel_getUid("alloc"));
        dp = ((id(*)(id,SEL,KRRect))objc_msgSend)(dp, sel_getUid("initWithFrame:"), r);
        // YearMonthDay only (no time) — matches Win32 DTS_SHORTDATEFORMAT.
        // Element flags: NSYearMonthDayDatePickerElementFlag = 0x00C0.
        MSG_V_L(dp, sel_getUid("setDatePickerElements:"), 0x00C0);
        // Style 0 = NSTextFieldAndStepperDatePickerStyle (textual + arrows).
        MSG_V_L(dp, sel_getUid("setDatePickerStyle:"), 0);

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(dp, id_int);
        MSG_V_O(dp, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(dp, sel_getUid("setAction:"), sel_getUid("krAction:"));

        MSG_V_O(container, sel_getUid("addSubview:"), dp);
        return kr_handle(dp);
    }

    // Format an NSDate as YYYY-MM-DD via NSCalendar so we match the
    // Win32 contract without pulling in NSDateFormatter (which needs
    // locale handling we don't want in a tiny C library).
    static char* kr_format_nsdate(id ns_date) {
        if (!ns_date) return kr_gui_dup("");
        id cal = MSG_O((id)objc_getClass("NSCalendar"), sel_getUid("currentCalendar"));
        // unitFlags: NSCalendarUnitYear|Month|Day = 4 | 8 | 16 = 28.
        id comps = ((id(*)(id,SEL,unsigned long,id))objc_msgSend)(
            cal, sel_getUid("components:fromDate:"), 28UL, ns_date);
        long y = MSG_L(comps, sel_getUid("year"));
        long m = MSG_L(comps, sel_getUid("month"));
        long d = MSG_L(comps, sel_getUid("day"));
        char out[16];
        snprintf(out, sizeof(out), "%04ld-%02ld-%02ld", y, m, d);
        return kr_gui_dup(out);
    }

    char* krGuiDateGet(char* hwnd_str) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl) return (char*)"";
        id ns_date = MSG_O(ctl, sel_getUid("dateValue"));
        return kr_format_nsdate(ns_date);
    }

    char* krGuiDateSet(char* hwnd_str, char* ymd) {
        id ctl = kr_resolve_control(hwnd_str);
        if (!ctl || !ymd) return (char*)"0";
        int y = 0, m = 0, d = 0;
        if (sscanf(ymd, "%d-%d-%d", &y, &m, &d) != 3) return (char*)"0";

        id comps = MSG_O(MSG_O((id)objc_getClass("NSDateComponents"), sel_getUid("alloc")),
                         sel_getUid("init"));
        MSG_V_L(comps, sel_getUid("setYear:"),  y);
        MSG_V_L(comps, sel_getUid("setMonth:"), m);
        MSG_V_L(comps, sel_getUid("setDay:"),   d);
        id cal = MSG_O((id)objc_getClass("NSCalendar"), sel_getUid("currentCalendar"));
        id ns_date = ((id(*)(id,SEL,id))objc_msgSend)(
            cal, sel_getUid("dateFromComponents:"), comps);
        if (!ns_date) return (char*)"0";
        MSG_V_O(ctl, sel_getUid("setDateValue:"), ns_date);
        return (char*)"1";
    }

    // ──────────────────────────────────────────────────────────────────
    // Round 5 widgets — tree view, status bar, toolbar.
    // ──────────────────────────────────────────────────────────────────

    // ── Tree view (NSOutlineView in NSScrollView) ────────────────
    //
    // Items are NSMutableDictionary { @"label", @"children" }; the
    // root NSMutableArray is attached to the outline view via
    // associated objects so the shared KrTreeHelper data source can
    // find it. guiTreeAdd returns the new node's hex pointer so it can
    // be passed back as the parent for nested adds.

    char* krGuiTreeView(char* parent, char* x_str, char* y_str, char* w_str, char* h_str) {
        kr_gui_bootstrap();
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id sv = MSG_O((id)objc_getClass("NSScrollView"), sel_getUid("alloc"));
        sv = ((id(*)(id,SEL,KRRect))objc_msgSend)(sv, sel_getUid("initWithFrame:"), r);
        MSG_V_C(sv, sel_getUid("setHasVerticalScroller:"), 1);
        MSG_V_L(sv, sel_getUid("setBorderType:"),          2);

        id tv = MSG_O((id)objc_getClass("NSOutlineView"), sel_getUid("alloc"));
        KRRect tvr = {{ 0, 0 }, { r.size.width, r.size.height }};
        tv = ((id(*)(id,SEL,KRRect))objc_msgSend)(tv, sel_getUid("initWithFrame:"), tvr);
        MSG_V_O(tv, sel_getUid("setHeaderView:"), NULL);
        MSG_V_C(tv, sel_getUid("setAllowsMultipleSelection:"), 0);

        id col = MSG_O((id)objc_getClass("NSTableColumn"), sel_getUid("alloc"));
        col = MSG_O_O(col, sel_getUid("initWithIdentifier:"), kr_ns_str("c0"));
        ((void(*)(id,SEL,double))objc_msgSend)(col, sel_getUid("setWidth:"),
                                               r.size.width - 4.0);
        MSG_V_O(tv, sel_getUid("addTableColumn:"),       col);
        MSG_V_O(tv, sel_getUid("setOutlineTableColumn:"), col);

        // Root NSMutableArray retained via the outline view.
        id root = MSG_O((id)objc_getClass("NSMutableArray"), sel_getUid("array"));
        objc_setAssociatedObject(tv, &kr_tree_root_key, root, 1);  // RETAIN_NONATOMIC

        if (g_tree_helper) {
            MSG_V_O(tv, sel_getUid("setDataSource:"), g_tree_helper);
            MSG_V_O(tv, sel_getUid("setDelegate:"),   g_tree_helper);
        }

        int slot_id = kr_register_cb_slot();
        kr_set_widget_tag(tv, slot_id);

        MSG_V_O(sv, sel_getUid("setDocumentView:"), tv);
        MSG_V_O(container, sel_getUid("addSubview:"), sv);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", slot_id);
        return kr_gui_dup(buf);
    }

    char* krGuiTreeAdd(char* tree_str, char* parent_item_str, char* label) {
        id tv = kr_resolve_control(tree_str);
        if (!tv) return (char*)"";

        // Empty / "0" / non-hex → add to root. Hex pointer → add as a
        // child of that node (assuming caller passed a node we returned
        // earlier). Out-of-band pointers are user bugs; not validated.
        id parent = NULL;
        if (parent_item_str && parent_item_str[0] == '0' && parent_item_str[1] == 'x') {
            parent = kr_obj_from(parent_item_str);
        }

        id node = MSG_O(MSG_O((id)objc_getClass("NSMutableDictionary"), sel_getUid("alloc")),
                        sel_getUid("init"));
        ((void(*)(id,SEL,id,id))objc_msgSend)(node, sel_getUid("setObject:forKey:"),
            kr_ns_str(label ? label : ""), kr_ns_str("label"));
        id children = MSG_O((id)objc_getClass("NSMutableArray"), sel_getUid("array"));
        ((void(*)(id,SEL,id,id))objc_msgSend)(node, sel_getUid("setObject:forKey:"),
            children, kr_ns_str("children"));

        id arr = NULL;
        if (parent) {
            arr = ((id(*)(id,SEL,id))objc_msgSend)(parent, sel_getUid("objectForKey:"),
                kr_ns_str("children"));
        } else {
            arr = (id)objc_getAssociatedObject(tv, &kr_tree_root_key);
        }
        if (arr) MSG_V_O(arr, sel_getUid("addObject:"), node);

        MSG_V(tv, sel_getUid("reloadData"));
        return kr_handle(node);
    }

    char* krGuiTreeClear(char* tree_str) {
        id tv = kr_resolve_control(tree_str);
        if (!tv) return (char*)"0";
        id root = (id)objc_getAssociatedObject(tv, &kr_tree_root_key);
        if (!root) return (char*)"0";
        MSG_V(root, sel_getUid("removeAllObjects"));
        MSG_V(tv, sel_getUid("reloadData"));
        return (char*)"1";
    }

    char* krGuiTreeSelected(char* tree_str) {
        id tv = kr_resolve_control(tree_str);
        if (!tv) return (char*)"";
        long row = MSG_L(tv, sel_getUid("selectedRow"));
        if (row < 0) return (char*)"";
        id item = ((id(*)(id,SEL,long))objc_msgSend)(tv, sel_getUid("itemAtRow:"), row);
        if (!item) return (char*)"";
        id label = ((id(*)(id,SEL,id))objc_msgSend)(item, sel_getUid("objectForKey:"),
            kr_ns_str("label"));
        if (!label) return (char*)"";
        return kr_ns_to_c(label);
    }

    // ── Status bar (faked: bottom-pinned NSView + NSTextField row) ─
    //
    // macOS doesn't have a native status bar; we approximate with a
    // 24-tall layer-backed view at the bottom of the contentView,
    // holding one NSTextField per "part". The parts CSV ("100,150,*")
    // resolves stars to "remaining width / count of stars".
    static char kr_status_parts_key;

    static id kr_status_make_part(KRRect r) {
        id tf = MSG_O((id)objc_getClass("NSTextField"), sel_getUid("alloc"));
        tf = ((id(*)(id,SEL,KRRect))objc_msgSend)(tf, sel_getUid("initWithFrame:"), r);
        MSG_V_C(tf, sel_getUid("setEditable:"),        0);
        MSG_V_C(tf, sel_getUid("setBezeled:"),         0);
        MSG_V_C(tf, sel_getUid("setDrawsBackground:"), 0);
        MSG_V_C(tf, sel_getUid("setSelectable:"),      0);
        MSG_V_O(tf, sel_getUid("setStringValue:"), kr_ns_str(""));
        return tf;
    }

    char* krGuiStatusBar(char* window_str) {
        kr_gui_bootstrap();
        id win = kr_obj_from(window_str);
        if (!win) win = g_main_window;
        if (!win) return (char*)"";
        id container = MSG_O(win, sel_getUid("contentView"));
        if (!container) return (char*)"";

        KRRect cf = ((KRRect(*)(id,SEL))objc_msgSend)(container, sel_getUid("frame"));
        const int bar_h = 24;
        KRRect br = {{ 0, cf.size.height - bar_h }, { cf.size.width, (double)bar_h }};

        Class viewCls = (Class)objc_getClass("KrFlippedView");
        if (!viewCls) viewCls = (Class)objc_getClass("NSView");
        id bar = MSG_O((id)viewCls, sel_getUid("alloc"));
        bar = ((id(*)(id,SEL,KRRect))objc_msgSend)(bar, sel_getUid("initWithFrame:"), br);
        // NSViewWidthSizable | NSViewMinYMargin → stretch horizontally,
        // anchor to the bottom edge of the contentView.
        MSG_V_L(bar, sel_getUid("setAutoresizingMask:"), 2 | 32);

        id parts = MSG_O((id)objc_getClass("NSMutableArray"), sel_getUid("array"));
        objc_setAssociatedObject(bar, &kr_status_parts_key, parts, 1);

        // Default: one part stretching the bar's full width.
        KRRect pr = {{ 6, 4 }, { cf.size.width - 12, (double)(bar_h - 8) }};
        id tf = kr_status_make_part(pr);
        MSG_V_O(bar, sel_getUid("addSubview:"), tf);
        MSG_V_O(parts, sel_getUid("addObject:"), tf);

        MSG_V_O(container, sel_getUid("addSubview:"), bar);
        return kr_handle(bar);
    }

    char* krGuiStatusParts(char* bar_str, char* widths) {
        id bar = kr_obj_from(bar_str);
        if (!bar) return (char*)"0";
        id parts = (id)objc_getAssociatedObject(bar, &kr_status_parts_key);
        if (!parts) return (char*)"0";

        long n_old = MSG_L(parts, sel_getUid("count"));
        for (long i = 0; i < n_old; i++) {
            id tf = ((id(*)(id,SEL,long))objc_msgSend)(parts, sel_getUid("objectAtIndex:"), i);
            MSG_V(tf, sel_getUid("removeFromSuperview"));
        }
        MSG_V(parts, sel_getUid("removeAllObjects"));

        KRRect br = ((KRRect(*)(id,SEL))objc_msgSend)(bar, sel_getUid("frame"));
        int total_w = (int)br.size.width;
        int total_h = (int)br.size.height;

        int parsed[16]; int n = 0;
        int fixed_w = 0;
        int n_stars = 0;
        char buf[256];
        size_t wlen = strlen(widths ? widths : "");
        if (wlen >= sizeof(buf)) wlen = sizeof(buf) - 1;
        memcpy(buf, widths ? widths : "", wlen);
        buf[wlen] = 0;

        char* p = buf;
        while (*p && n < 16) {
            while (*p == ',' || *p == ' ') p++;
            if (!*p) break;
            if (*p == '*') {
                parsed[n++] = -1;
                n_stars++;
                p++;
            } else {
                int w = atoi(p);
                parsed[n++] = w;
                fixed_w += w;
                while (*p && *p != ',') p++;
            }
        }
        if (n == 0) { parsed[0] = -1; n = 1; n_stars = 1; }
        int star_w = (n_stars > 0) ? (total_w - fixed_w) / n_stars : 0;
        if (star_w < 0) star_w = 0;

        int cursor = 6;
        int avail_h = total_h - 8;
        for (int i = 0; i < n; i++) {
            int w = (parsed[i] < 0) ? star_w : parsed[i];
            KRRect pr = {{ (double)cursor, 4 }, { (double)(w - 4), (double)avail_h }};
            id tf = kr_status_make_part(pr);
            MSG_V_O(bar, sel_getUid("addSubview:"), tf);
            MSG_V_O(parts, sel_getUid("addObject:"), tf);
            cursor += w;
        }
        return (char*)"1";
    }

    char* krGuiStatusSet(char* bar_str, char* idx_str, char* text) {
        id bar = kr_obj_from(bar_str);
        if (!bar) return (char*)"0";
        id parts = (id)objc_getAssociatedObject(bar, &kr_status_parts_key);
        if (!parts) return (char*)"0";
        long idx = atol(idx_str ? idx_str : "0");
        long n = MSG_L(parts, sel_getUid("count"));
        if (idx < 0 || idx >= n) return (char*)"0";
        id tf = ((id(*)(id,SEL,long))objc_msgSend)(parts, sel_getUid("objectAtIndex:"), idx);
        MSG_V_O(tf, sel_getUid("setStringValue:"), kr_ns_str(text ? text : ""));
        return (char*)"1";
    }

    char* krGuiStatusGet(char* bar_str, char* idx_str) {
        id bar = kr_obj_from(bar_str);
        if (!bar) return (char*)"";
        id parts = (id)objc_getAssociatedObject(bar, &kr_status_parts_key);
        if (!parts) return (char*)"";
        long idx = atol(idx_str ? idx_str : "0");
        long n = MSG_L(parts, sel_getUid("count"));
        if (idx < 0 || idx >= n) return (char*)"";
        id tf = ((id(*)(id,SEL,long))objc_msgSend)(parts, sel_getUid("objectAtIndex:"), idx);
        return kr_ns_to_c(MSG_O(tf, sel_getUid("stringValue")));
    }

    // Cocoa NSTextField doesn't carry a system-icon slot like the Win32
    // status bar's ICON column, and there's no good cross-platform mapping
    // for "info" / "warning" / "error" names. Leave as a no-op for now.
    char* krGuiStatusIcon(char* bar_str, char* idx_str, char* iconName) {
        (void)bar_str; (void)idx_str; (void)iconName;
        return (char*)"0";
    }

    char* krGuiStatusBgColor(char* bar_str, char* hex) {
        id bar = kr_obj_from(bar_str);
        if (!bar) return (char*)"0";

        const char* p = hex ? hex : "";
        if (*p == '#') p++;
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
        unsigned int v = 0;
        sscanf(p, "%x", &v);
        double r = ((v >> 16) & 0xFF) / 255.0;
        double g = ((v >> 8)  & 0xFF) / 255.0;
        double b = ( v        & 0xFF) / 255.0;

        // CALayer background needs the view to be layer-backed.
        MSG_V_C(bar, sel_getUid("setWantsLayer:"), 1);
        id layer = MSG_O(bar, sel_getUid("layer"));
        if (!layer) return (char*)"0";

        id color = ((id(*)(id,SEL,double,double,double,double))objc_msgSend)(
            (id)objc_getClass("NSColor"),
            sel_getUid("colorWithRed:green:blue:alpha:"),
            r, g, b, 1.0);
        // -[NSColor CGColor] returns a CGColorRef, which is toll-free
        // bridged to id for CALayer's setBackgroundColor:.
        id cgColor = MSG_O(color, sel_getUid("CGColor"));
        MSG_V_O(layer, sel_getUid("setBackgroundColor:"), cgColor);
        return (char*)"1";
    }

    // ── Toolbar (top-pinned NSView with horizontal NSButton row) ──
    //
    // Win32's TOOLBARCLASSNAMEW is just a strip of buttons; Cocoa has
    // a fully-fledged NSToolbar with delegate-driven item identifiers,
    // but for parity with the Win32 contract the simpler "buttons in a
    // bar" approach is what user code actually expects from
    // guiToolbar / guiToolButton. NSToolbar can come later.
    static char kr_toolbar_cursor_key;

    static int kr_tb_cursor(id bar) {
        id num = (id)objc_getAssociatedObject(bar, &kr_toolbar_cursor_key);
        if (!num) return 4;
        return (int)MSG_L(num, sel_getUid("longValue"));
    }

    static void kr_tb_set_cursor(id bar, int x) {
        id num = ((id(*)(id,SEL,long))objc_msgSend)(
            (id)objc_getClass("NSNumber"),
            sel_getUid("numberWithLong:"),
            (long)x);
        objc_setAssociatedObject(bar, &kr_toolbar_cursor_key, num, 1);
    }

    char* krGuiToolbar(char* window_str) {
        kr_gui_bootstrap();
        id win = kr_obj_from(window_str);
        if (!win) win = g_main_window;
        if (!win) return (char*)"";
        id container = MSG_O(win, sel_getUid("contentView"));
        if (!container) return (char*)"";

        KRRect cf = ((KRRect(*)(id,SEL))objc_msgSend)(container, sel_getUid("frame"));
        const int bar_h = 32;
        KRRect br = {{ 0, 0 }, { cf.size.width, (double)bar_h }};

        Class viewCls = (Class)objc_getClass("KrFlippedView");
        if (!viewCls) viewCls = (Class)objc_getClass("NSView");
        id bar = MSG_O((id)viewCls, sel_getUid("alloc"));
        bar = ((id(*)(id,SEL,KRRect))objc_msgSend)(bar, sel_getUid("initWithFrame:"), br);
        MSG_V_L(bar, sel_getUid("setAutoresizingMask:"), 2);   // NSViewWidthSizable

        // Subtle gray tint so the bar reads as chrome, not content.
        MSG_V_C(bar, sel_getUid("setWantsLayer:"), 1);
        id layer = MSG_O(bar, sel_getUid("layer"));
        if (layer) {
            id color = ((id(*)(id,SEL,double,double,double,double))objc_msgSend)(
                (id)objc_getClass("NSColor"),
                sel_getUid("colorWithRed:green:blue:alpha:"),
                0.92, 0.92, 0.92, 1.0);
            MSG_V_O(layer, sel_getUid("setBackgroundColor:"),
                    MSG_O(color, sel_getUid("CGColor")));
        }

        kr_tb_set_cursor(bar, 4);
        MSG_V_O(container, sel_getUid("addSubview:"), bar);
        return kr_handle(bar);
    }

    char* krGuiToolButton(char* tb_str, char* label, char* iconName) {
        (void)iconName;     // Win32 standard-icon names don't map to Cocoa
        id bar = kr_obj_from(tb_str);
        if (!bar) return (char*)"";
        int cursor = kr_tb_cursor(bar);

        // Rough sizing: 8px/char + 28px padding, 60px floor. Good enough
        // to match the auto-sized Win32 BTNS_AUTOSIZE behavior.
        int w = (int)strlen(label ? label : "") * 8 + 28;
        if (w < 60) w = 60;

        KRRect r = {{ (double)cursor, 4 }, { (double)w, 24 }};
        id btn = MSG_O((id)objc_getClass("NSButton"), sel_getUid("alloc"));
        btn = ((id(*)(id,SEL,KRRect))objc_msgSend)(btn, sel_getUid("initWithFrame:"), r);
        MSG_V_O(btn, sel_getUid("setTitle:"), kr_ns_str(label ? label : ""));
        MSG_V_L(btn, sel_getUid("setBezelStyle:"), 1);    // NSBezelStyleRounded
        MSG_V_O(btn, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(btn, sel_getUid("setAction:"), sel_getUid("krAction:"));

        int id_int = kr_register_cb_slot();
        kr_set_widget_tag(btn, id_int);
        MSG_V_O(bar, sel_getUid("addSubview:"), btn);

        kr_tb_set_cursor(bar, cursor + w + 4);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", id_int);
        return kr_gui_dup(buf);
    }

    char* krGuiToolSep(char* tb_str) {
        id bar = kr_obj_from(tb_str);
        if (!bar) return (char*)"0";
        // Just leave a 12px gap. A vertical line would be nicer but
        // the visual delta in a flat toolbar is small.
        kr_tb_set_cursor(bar, kr_tb_cursor(bar) + 12);
        return (char*)"1";
    }

    char* krGuiToolbarHeight(char* tb_str) {
        (void)tb_str;
        return kr_gui_dup("32");
    }

    // ──────────────────────────────────────────────────────────────────
    // Round 6 widgets — dock manager, color picker, scrollbar.
    // ──────────────────────────────────────────────────────────────────

    // ── Dock layout (top/bottom/left/right/fill, edge-eating) ────
    //
    // Returns a hex pointer to a kr_dock_state. The user calls
    // guiDockTop / Bottom / Left / Right / Fill to register kids,
    // then guiDockApply to do the initial layout. After that the
    // dock listens for NSWindowDidResizeNotification and reflows
    // automatically — the krDockResize: selector wired in bootstrap
    // handles dispatch.
    char* krGuiDock(char* window_str) {
        kr_gui_bootstrap();
        id win = kr_obj_from(window_str);
        if (!win) win = g_main_window;
        if (!win) return (char*)"";
        if (g_n_docks >= KR_GUI_MAX_DOCKS) return (char*)"";

        kr_dock_state* d = (kr_dock_state*)calloc(1, sizeof(*d));
        if (!d) return (char*)"";
        d->window  = win;
        d->content = MSG_O(win, sel_getUid("contentView"));
        g_docks[g_n_docks++] = d;

        // One-shot per-window observer. Adding it more than once is
        // harmless (NSNotificationCenter dedupes (target, sel, name)
        // tuples it has seen) but cheaper to gate on first dock.
        id center = MSG_O((id)objc_getClass("NSNotificationCenter"),
                          sel_getUid("defaultCenter"));
        ((void(*)(id,SEL,id,SEL,id,id))objc_msgSend)(
            center, sel_getUid("addObserver:selector:name:object:"),
            g_target,
            sel_getUid("krDockResize:"),
            kr_ns_str("NSWindowDidResizeNotification"),
            win);

        char buf[32];
        snprintf(buf, sizeof(buf), "%p", (void*)d);
        return kr_gui_dup(buf);
    }

    static kr_dock_state* kr_dock_resolve(const char* h) {
        if (!h || h[0] != '0' || h[1] != 'x') return NULL;
        void* p = NULL;
        if (sscanf(h, "%p", &p) != 1) return NULL;
        return (kr_dock_state*)p;
    }

    // Resolve a child handle that may be either a hex pointer (text
    // area, scroll view, image, etc.) or a decimal id (button-style
    // tag — sliders, tree views, splitters). The dock layout calls
    // -setFrame: on the resolved view, so we go through the same
    // tag-aware lookup the rest of the API uses.
    static id kr_dock_resolve_child(const char* h) {
        if (!h) return NULL;
        if (h[0] == '0' && h[1] == 'x') return kr_obj_from(h);
        // Treat as decimal tag — walk the contentView's full subview
        // tree. Most listbox/textarea/treeview handles are NSScrollView
        // pointers (hex), but slider-style decimal-tag handles need
        // tag-walk. kr_resolve_control already does shallow walks; we
        // want recursive in case the widget lives inside a container.
        long want = atol(h);
        if (want < 1000) return NULL;
        if (!g_main_window) return NULL;
        id content = MSG_O(g_main_window, sel_getUid("contentView"));
        if (!content) return NULL;
        // BFS-ish walk via subviews
        id arr = MSG_O(content, sel_getUid("subviews"));
        long n = MSG_L(arr, sel_getUid("count"));
        for (long i = 0; i < n; i++) {
            id v = ((id(*)(id,SEL,long))objc_msgSend)(arr, sel_getUid("objectAtIndex:"), i);
            if (kr_get_widget_tag(v) == want) return v;
        }
        return NULL;
    }

    static char* kr_dock_add(char* dock_str, char* h_str, int side, int size) {
        kr_dock_state* d = kr_dock_resolve(dock_str);
        if (!d || d->n_kids >= 64) return (char*)"0";
        id v = kr_dock_resolve_child(h_str);
        if (!v) return (char*)"0";
        d->kids[d->n_kids].view = v;
        d->kids[d->n_kids].side = side;
        d->kids[d->n_kids].size = size;
        d->n_kids++;
        return (char*)"1";
    }

    char* krGuiDockTop(char* d, char* h, char* s)    { return kr_dock_add(d, h, 0, atoi(s ? s : "0")); }
    char* krGuiDockBottom(char* d, char* h, char* s) { return kr_dock_add(d, h, 1, atoi(s ? s : "0")); }
    char* krGuiDockLeft(char* d, char* h, char* s)   { return kr_dock_add(d, h, 2, atoi(s ? s : "0")); }
    char* krGuiDockRight(char* d, char* h, char* s)  { return kr_dock_add(d, h, 3, atoi(s ? s : "0")); }
    char* krGuiDockFill(char* d, char* h)            { return kr_dock_add(d, h, 4, 0); }

    char* krGuiDockApply(char* d_str) {
        kr_dock_state* d = kr_dock_resolve(d_str);
        if (!d) return (char*)"0";
        kr_dock_layout(d);
        return (char*)"1";
    }

    // ── Color picker (NSAlert + NSColorWell accessory) ──────────
    //
    // ChooseColorW is a fully modal blocking dialog on Win32. Cocoa's
    // NSColorPanel is an async floating utility, so to keep the same
    // synchronous "open → return" contract we wrap an NSColorWell in
    // an NSAlert: the user clicks the well to open the system picker,
    // adjusts, then clicks OK or Cancel on the alert.
    char* krGuiColorPicker(char* initialHex) {
        kr_gui_bootstrap();

        unsigned int v = 0;
        if (initialHex && *initialHex) {
            const char* p = initialHex;
            if (*p == '#') p++;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
            sscanf(p, "%x", &v);
        }
        double r = ((v >> 16) & 0xFF) / 255.0;
        double g = ((v >> 8)  & 0xFF) / 255.0;
        double b = ( v        & 0xFF) / 255.0;

        KRRect well_r = {{ 0, 0 }, { 220, 80 }};
        id well = MSG_O((id)objc_getClass("NSColorWell"), sel_getUid("alloc"));
        well = ((id(*)(id,SEL,KRRect))objc_msgSend)(well, sel_getUid("initWithFrame:"), well_r);
        id init_color = ((id(*)(id,SEL,double,double,double,double))objc_msgSend)(
            (id)objc_getClass("NSColor"),
            sel_getUid("colorWithRed:green:blue:alpha:"),
            r, g, b, 1.0);
        MSG_V_O(well, sel_getUid("setColor:"), init_color);

        id alert = MSG_O((id)objc_getClass("NSAlert"), sel_getUid("alloc"));
        alert = MSG_O(alert, sel_getUid("init"));
        MSG_V_O(alert, sel_getUid("setMessageText:"),     kr_ns_str("Pick a color"));
        MSG_V_O(alert, sel_getUid("setInformativeText:"), kr_ns_str("Click the swatch to open the color picker."));
        MSG_V_O(alert, sel_getUid("setAccessoryView:"),   well);
        MSG_V_O(alert, sel_getUid("addButtonWithTitle:"), kr_ns_str("OK"));
        MSG_V_O(alert, sel_getUid("addButtonWithTitle:"), kr_ns_str("Cancel"));
        long resp = ((long(*)(id,SEL))objc_msgSend)(alert, sel_getUid("runModal"));
        if (resp != 1000) return (char*)"";   // NSAlertFirstButtonReturn = 1000

        // Coerce to sRGB so component reads return 0..1 floats reliably.
        id color = MSG_O(well, sel_getUid("color"));
        id rgb = ((id(*)(id,SEL,id))objc_msgSend)(
            color, sel_getUid("colorUsingColorSpace:"),
            MSG_O((id)objc_getClass("NSColorSpace"), sel_getUid("sRGBColorSpace")));
        if (!rgb) rgb = color;

        double red   = ((double(*)(id,SEL))objc_msgSend)(rgb, sel_getUid("redComponent"));
        double green = ((double(*)(id,SEL))objc_msgSend)(rgb, sel_getUid("greenComponent"));
        double blue  = ((double(*)(id,SEL))objc_msgSend)(rgb, sel_getUid("blueComponent"));
        int R = (int)(red   * 255 + 0.5); if (R < 0) R = 0; if (R > 255) R = 255;
        int G = (int)(green * 255 + 0.5); if (G < 0) G = 0; if (G > 255) G = 255;
        int B = (int)(blue  * 255 + 0.5); if (B < 0) B = 0; if (B > 255) B = 255;

        char out[16];
        snprintf(out, sizeof(out), "0x%02X%02X%02X", R, G, B);
        return kr_gui_dup(out);
    }

    // ── Scrollbar (NSScroller, value/range mapping) ─────────────
    //
    // NSScroller's natural API speaks 0..1 floatValue + knobProportion.
    // The Win32 SCROLLBAR contract is integer (lo, hi, page, value), so
    // we cache range state on each scroller via an associated struct
    // and translate at the boundary.
    typedef struct {
        int lo, hi, page;
        int value;
    } kr_scrollbar_state;
    static char kr_scrollbar_state_key;

    static void kr_scrollbar_apply(id sc, kr_scrollbar_state* s) {
        int total = s->hi - s->lo;
        double prop = (total > 0) ? (double)s->page / (double)total : 0.0;
        if (prop < 0.05) prop = 0.05;
        if (prop > 1.0)  prop = 1.0;
        int span = total - s->page;
        double frac = (span > 0) ? (double)(s->value - s->lo) / (double)span : 0.0;
        if (frac < 0) frac = 0;
        if (frac > 1) frac = 1;
        ((void(*)(id,SEL,double,double))objc_msgSend)(
            sc, sel_getUid("setFloatValue:knobProportion:"), frac, prop);
    }

    char* krGuiScrollbar(char* parent, char* x_str, char* y_str, char* w_str, char* h_str, char* vert_str) {
        (void)vert_str;   // NSScroller picks orientation from frame aspect
        id container = kr_resolve_container(parent);
        if (!container) return (char*)"";
        KRRect r = {{ (double)atoi(x_str), (double)atoi(y_str) },
                    { (double)atoi(w_str), (double)atoi(h_str) }};

        id sc = MSG_O((id)objc_getClass("NSScroller"), sel_getUid("alloc"));
        sc = ((id(*)(id,SEL,KRRect))objc_msgSend)(sc, sel_getUid("initWithFrame:"), r);
        MSG_V_C(sc, sel_getUid("setEnabled:"), 1);
        // Modern macOS scrollers default to overlay style; force the
        // legacy always-visible style so a standalone bar is actually
        // visible without scrolling content underneath it.
        MSG_V_L(sc, sel_getUid("setScrollerStyle:"), 0);   // NSScrollerStyleLegacy

        kr_scrollbar_state* s = (kr_scrollbar_state*)malloc(sizeof(*s));
        s->lo = 0; s->hi = 100; s->page = 10; s->value = 0;
        objc_setAssociatedObject(sc, &kr_scrollbar_state_key, (id)s, 0);  // ASSIGN
        kr_scrollbar_apply(sc, s);

        MSG_V_O(sc, sel_getUid("setTarget:"), g_target);
        MSG_V_SEL(sc, sel_getUid("setAction:"), sel_getUid("krAction:"));

        int slot_id = kr_register_cb_slot();
        kr_set_widget_tag(sc, slot_id);
        MSG_V_O(container, sel_getUid("addSubview:"), sc);

        char buf[16];
        snprintf(buf, sizeof(buf), "%d", slot_id);
        return kr_gui_dup(buf);
    }

    char* krGuiScrollbarRange(char* sb_str, char* lo_str, char* hi_str, char* page_str) {
        id sc = kr_resolve_control(sb_str);
        if (!sc) return (char*)"0";
        kr_scrollbar_state* s = (kr_scrollbar_state*)objc_getAssociatedObject(
            sc, &kr_scrollbar_state_key);
        if (!s) return (char*)"0";
        s->lo   = atoi(lo_str   ? lo_str   : "0");
        s->hi   = atoi(hi_str   ? hi_str   : "100");
        s->page = atoi(page_str ? page_str : "10");
        kr_scrollbar_apply(sc, s);
        return (char*)"1";
    }

    char* krGuiScrollbarValue(char* sb_str) {
        id sc = kr_resolve_control(sb_str);
        if (!sc) return (char*)"0";
        kr_scrollbar_state* s = (kr_scrollbar_state*)objc_getAssociatedObject(
            sc, &kr_scrollbar_state_key);
        if (!s) return (char*)"0";
        // Pull the live floatValue back through and convert to an int,
        // so a drag is reflected even between explicit Set calls.
        double frac = ((double(*)(id,SEL))objc_msgSend)(sc, sel_getUid("doubleValue"));
        int span = s->hi - s->lo - s->page;
        if (span < 0) span = 0;
        s->value = s->lo + (int)(frac * (double)span + 0.5);
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", s->value);
        return kr_gui_dup(buf);
    }

    char* krGuiScrollbarSet(char* sb_str, char* v_str) {
        id sc = kr_resolve_control(sb_str);
        if (!sc) return (char*)"0";
        kr_scrollbar_state* s = (kr_scrollbar_state*)objc_getAssociatedObject(
            sc, &kr_scrollbar_state_key);
        if (!s) return (char*)"0";
        s->value = atoi(v_str ? v_str : "0");
        kr_scrollbar_apply(sc, s);
        return (char*)"1";
    }

    // RichEdit — Win32-only widget. macOS gets no-op stubs so apps that
    // use guiRichEdit on the Mac don't crash; they just see an empty
    // handle and the format/append calls become no-ops.
    char* krGuiRichEdit(char* p, char* x, char* y, char* w, char* h)        { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiRichSetFmt(char* r, char* s, char* e, char* c, char* b)      { (void)r;(void)s;(void)e;(void)c;(void)b; return (char*)"0"; }
    char* krGuiRichClearFmt(char* r)                                        { (void)r; return (char*)"0"; }
    char* krGuiRichAppend(char* r, char* t, char* c, char* b)               { (void)r;(void)t;(void)c;(void)b; return (char*)"0"; }
    char* krGuiRichReadOnly(char* r, char* o)                               { (void)r;(void)o; return (char*)"0"; }
    char* krGuiRichSetMonoFont(char* r, char* f, char* p)                   { (void)r;(void)f;(void)p; return (char*)"0"; }

    #undef KR_STUB_S
    #undef KR_STUB_0

#else
    // ──────────────────────────────────────────────────────────────────
    // Fallback (Linux etc.) — every entry point is a no-op stub so the
    // module at least links. A native GTK / X11 backend can replace
    // this block when someone gets to it.
    // ──────────────────────────────────────────────────────────────────

    char* krGuiInit(void)                                                                          { return (char*)"0"; }
    char* krGuiWindow(char* t, char* w, char* h)                                                   { (void)t;(void)w;(void)h; return (char*)""; }
    char* krGuiShow(char* h)                                                                       { (void)h; return (char*)"0"; }
    char* krGuiButton(char* p, char* l, char* x, char* y, char* w, char* h)                       { (void)p;(void)l;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiLabel(char* p, char* t, char* x, char* y, char* w, char* h)                       { (void)p;(void)t;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiTextInput(char* p, char* x, char* y, char* w, char* h)                             { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiTextArea(char* p, char* x, char* y, char* w, char* h)                              { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiRichEdit(char* p, char* x, char* y, char* w, char* h)                              { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiRichSetFmt(char* r, char* s, char* e, char* c, char* b)                            { (void)r;(void)s;(void)e;(void)c;(void)b; return (char*)"0"; }
    char* krGuiRichClearFmt(char* r)                                                              { (void)r; return (char*)"0"; }
    char* krGuiRichAppend(char* r, char* t, char* c, char* b)                                     { (void)r;(void)t;(void)c;(void)b; return (char*)"0"; }
    char* krGuiRichReadOnly(char* r, char* o)                                                     { (void)r;(void)o; return (char*)"0"; }
    char* krGuiRichSetMonoFont(char* r, char* f, char* p)                                         { (void)r;(void)f;(void)p; return (char*)"0"; }
    char* krGuiCheckbox(char* p, char* l, char* x, char* y, char* w, char* h)                    { (void)p;(void)l;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiIsChecked(char* h)                                                                 { (void)h; return (char*)"0"; }
    char* krGuiSetChecked(char* h, char* o)                                                       { (void)h;(void)o; return (char*)"0"; }
    char* krGuiListbox(char* p, char* x, char* y, char* w, char* h)                              { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiListAdd(char* h, char* i)                                                          { (void)h;(void)i; return (char*)"0"; }
    char* krGuiListClear(char* h)                                                                 { (void)h; return (char*)"0"; }
    char* krGuiListSelected(char* h)                                                              { (void)h; return (char*)""; }
    char* krGuiProgress(char* p, char* x, char* y, char* w, char* h)                             { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiProgressSet(char* h, char* p)                                                      { (void)h;(void)p; return (char*)"0"; }
    char* krGuiTreeView(char* p, char* x, char* y, char* w, char* h)                             { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiTreeAdd(char* t, char* pi, char* l)                                                { (void)t;(void)pi;(void)l; return (char*)""; }
    char* krGuiTreeClear(char* t)                                                                 { (void)t; return (char*)"0"; }
    char* krGuiTreeSelected(char* t)                                                              { (void)t; return (char*)""; }
    char* krGuiTabs(char* p, char* x, char* y, char* w, char* h)                                 { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiTabAdd(char* t, char* l)                                                           { (void)t;(void)l; return (char*)""; }
    char* krGuiTabSelected(char* t)                                                               { (void)t; return (char*)""; }
    char* krGuiOnChange(char* h, char* s)                                                         { (void)h;(void)s; return (char*)"0"; }
    char* krGuiMenuBegin(char* w)                                                                 { (void)w; return (char*)""; }
    char* krGuiMenu(char* mb, char* l)                                                            { (void)mb;(void)l; return (char*)""; }
    char* krGuiMenuItem(char* p, char* l)                                                         { (void)p;(void)l; return (char*)""; }
    char* krGuiMenuSeparator(char* p)                                                             { (void)p; return (char*)"0"; }
    char* krGuiMenuAdd(char* m, char* l)                                                          { (void)m;(void)l; return (char*)""; }
    char* krGuiStatusBar(char* w)                                                                 { (void)w; return (char*)""; }
    char* krGuiStatusParts(char* b, char* c)                                                      { (void)b;(void)c; return (char*)"0"; }
    char* krGuiStatusSet(char* b, char* i, char* t)                                               { (void)b;(void)i;(void)t; return (char*)"0"; }
    char* krGuiStatusGet(char* b, char* i)                                                        { (void)b;(void)i; return (char*)""; }
    char* krGuiStatusIcon(char* b, char* i, char* n)                                              { (void)b;(void)i;(void)n; return (char*)"0"; }
    char* krGuiStatusBgColor(char* b, char* h)                                                    { (void)b;(void)h; return (char*)"0"; }
    char* krGuiMove(char* h, char* x, char* y, char* w, char* hh)                                 { (void)h;(void)x;(void)y;(void)w;(void)hh; return (char*)"0"; }
    char* krGuiDock(char* w)                                                                      { (void)w; return (char*)""; }
    char* krGuiDockTop(char* d, char* h, char* s)                                                 { (void)d;(void)h;(void)s; return (char*)"0"; }
    char* krGuiDockBottom(char* d, char* h, char* s)                                              { (void)d;(void)h;(void)s; return (char*)"0"; }
    char* krGuiDockLeft(char* d, char* h, char* s)                                                { (void)d;(void)h;(void)s; return (char*)"0"; }
    char* krGuiDockRight(char* d, char* h, char* s)                                               { (void)d;(void)h;(void)s; return (char*)"0"; }
    char* krGuiDockFill(char* d, char* h)                                                         { (void)d;(void)h; return (char*)"0"; }
    char* krGuiDockApply(char* d)                                                                 { (void)d; return (char*)"0"; }
    char* krGuiSplitter(char* p, char* x, char* y, char* w, char* h, char* o)                    { (void)p;(void)x;(void)y;(void)w;(void)h;(void)o; return (char*)""; }
    char* krGuiSplitterPos(char* s)                                                               { (void)s; return (char*)""; }
    char* krGuiCombo(char* p, char* x, char* y, char* w, char* h)                                { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiComboAdd(char* c, char* i)                                                         { (void)c;(void)i; return (char*)"0"; }
    char* krGuiComboClear(char* c)                                                                { (void)c; return (char*)"0"; }
    char* krGuiComboSelected(char* c)                                                             { (void)c; return (char*)""; }
    char* krGuiComboSet(char* c, char* i)                                                         { (void)c;(void)i; return (char*)"0"; }
    char* krGuiColorPicker(char* h)                                                               { (void)h; return (char*)""; }
    char* krGuiDatePicker(char* p, char* x, char* y, char* w, char* h)                           { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiDateGet(char* p)                                                                   { (void)p; return (char*)""; }
    char* krGuiDateSet(char* p, char* y)                                                          { (void)p;(void)y; return (char*)"0"; }
    char* krGuiScrollbar(char* p, char* x, char* y, char* w, char* h, char* v)                   { (void)p;(void)x;(void)y;(void)w;(void)h;(void)v; return (char*)""; }
    char* krGuiScrollbarRange(char* s, char* lo, char* hi, char* pg)                              { (void)s;(void)lo;(void)hi;(void)pg; return (char*)"0"; }
    char* krGuiScrollbarValue(char* s)                                                            { (void)s; return (char*)""; }
    char* krGuiScrollbarSet(char* s, char* v)                                                     { (void)s;(void)v; return (char*)"0"; }
    char* krGuiVStack(char* p, char* x, char* y, char* w, char* g)                                { (void)p;(void)x;(void)y;(void)w;(void)g; return (char*)""; }
    char* krGuiHStack(char* p, char* x, char* y, char* h, char* g)                                { (void)p;(void)x;(void)y;(void)h;(void)g; return (char*)""; }
    char* krGuiVNext(char* s, char* h)                                                            { (void)s;(void)h; return (char*)""; }
    char* krGuiHNext(char* s, char* w)                                                            { (void)s;(void)w; return (char*)""; }
    char* krGuiStackParent(char* s)                                                               { (void)s; return (char*)""; }
    char* krGuiStackX(char* s)                                                                    { (void)s; return (char*)"0"; }
    char* krGuiStackY(char* s)                                                                    { (void)s; return (char*)"0"; }
    char* krGuiStackW(char* s)                                                                    { (void)s; return (char*)"0"; }
    char* krGuiStackH(char* s)                                                                    { (void)s; return (char*)"0"; }
    char* krGuiStackGap(char* s)                                                                  { (void)s; return (char*)"0"; }
    char* krGuiStackGapAdd(char* s, char* p)                                                      { (void)s;(void)p; return (char*)"0"; }
    char* krGuiImage(char* p, char* pa, char* x, char* y, char* w, char* h)                      { (void)p;(void)pa;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiImageSet(char* i, char* p)                                                         { (void)i;(void)p; return (char*)"0"; }
    char* krGuiSlider(char* p, char* x, char* y, char* w, char* h)                               { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiSliderRange(char* s, char* lo, char* hi)                                           { (void)s;(void)lo;(void)hi; return (char*)"0"; }
    char* krGuiSliderSet(char* s, char* v)                                                        { (void)s;(void)v; return (char*)"0"; }
    char* krGuiSliderValue(char* s)                                                               { (void)s; return (char*)"0"; }
    char* krGuiSpinbox(char* p, char* x, char* y, char* w, char* h)                              { (void)p;(void)x;(void)y;(void)w;(void)h; return (char*)""; }
    char* krGuiSpinboxRange(char* s, char* lo, char* hi)                                          { (void)s;(void)lo;(void)hi; return (char*)"0"; }
    char* krGuiSpinboxSet(char* s, char* v)                                                       { (void)s;(void)v; return (char*)"0"; }
    char* krGuiSpinboxValue(char* s)                                                              { (void)s; return (char*)"0"; }
    char* krGuiToolbar(char* w)                                                                   { (void)w; return (char*)""; }
    char* krGuiToolButton(char* tb, char* l, char* i)                                             { (void)tb;(void)l;(void)i; return (char*)""; }
    char* krGuiToolSep(char* tb)                                                                  { (void)tb; return (char*)"0"; }
    char* krGuiToolbarHeight(char* tb)                                                            { (void)tb; return (char*)"0"; }
    char* krGuiOpenFile(char* t, char* f)                                                         { (void)t;(void)f; return (char*)""; }
    char* krGuiSaveFile(char* t, char* f, char* d)                                                { (void)t;(void)f;(void)d; return (char*)""; }
    char* krGuiPickFolder(char* t)                                                                { (void)t; return (char*)""; }
    char* krGuiSetText(char* h, char* t)                                                          { (void)h;(void)t; return (char*)"0"; }
    char* krGuiGetText(char* h)                                                                   { (void)h; return (char*)""; }
    char* krGuiOnClick(char* h, char* s)                                                          { (void)h;(void)s; return (char*)"0"; }
    char* krGuiMessageBox(char* t, char* m)                                                       { (void)t;(void)m; return (char*)"0"; }
    char* krGuiRun(void)                                                                          { return (char*)"0"; }
    char* krGuiQuit(void)                                                                         { return (char*)"0"; }

#endif
}


// ── Krypton public API ─────────────────────────────────────────

func guiInit()                                   { emit krGuiInit() }
func guiWindow(title, w, h)                      { emit krGuiWindow(title, w + "", h + "") }
func guiShow(hwnd)                               { emit krGuiShow(hwnd) }
func guiButton(parent, label, x, y, w, h)        { emit krGuiButton(parent, label, x + "", y + "", w + "", h + "") }
func guiLabel(parent, text, x, y, w, h)          { emit krGuiLabel(parent, text, x + "", y + "", w + "", h + "") }
func guiTextInput(parent, x, y, w, h)            { emit krGuiTextInput(parent, x + "", y + "", w + "", h + "") }
func guiTextArea(parent, x, y, w, h)             { emit krGuiTextArea(parent, x + "", y + "", w + "", h + "") }
func guiRichEdit(parent, x, y, w, h)             { emit krGuiRichEdit(parent, x + "", y + "", w + "", h + "") }
func guiRichSetFmt(rich, start, end, hexColor, bold) { emit krGuiRichSetFmt(rich, start + "", end + "", hexColor, bold + "") }
func guiRichClearFmt(rich)                       { emit krGuiRichClearFmt(rich) }
func guiRichAppend(rich, text, hexColor, bold)   { emit krGuiRichAppend(rich, text, hexColor, bold + "") }
func guiRichReadOnly(rich, on)                   { emit krGuiRichReadOnly(rich, on + "") }
func guiRichSetMonoFont(rich, family, ptSize)    { emit krGuiRichSetMonoFont(rich, family, ptSize + "") }
func guiCheckbox(parent, label, x, y, w, h)      { emit krGuiCheckbox(parent, label, x + "", y + "", w + "", h + "") }
func guiIsChecked(hwnd)                          { emit krGuiIsChecked(hwnd) }
func guiSetChecked(hwnd, on)                     { emit krGuiSetChecked(hwnd, on + "") }
func guiListbox(parent, x, y, w, h)              { emit krGuiListbox(parent, x + "", y + "", w + "", h + "") }
func guiListAdd(hwnd, item)                      { emit krGuiListAdd(hwnd, item) }
func guiListClear(hwnd)                          { emit krGuiListClear(hwnd) }
func guiListSelected(hwnd)                       { emit krGuiListSelected(hwnd) }
func guiProgress(parent, x, y, w, h)             { emit krGuiProgress(parent, x + "", y + "", w + "", h + "") }
func guiProgressSet(hwnd, percent)               { emit krGuiProgressSet(hwnd, percent + "") }
func guiTreeView(parent, x, y, w, h)             { emit krGuiTreeView(parent, x + "", y + "", w + "", h + "") }
func guiTreeAdd(tree, parent_item, label)        { emit krGuiTreeAdd(tree, parent_item, label) }
func guiTreeClear(tree)                          { emit krGuiTreeClear(tree) }
func guiTreeSelected(tree)                       { emit krGuiTreeSelected(tree) }
func guiTabs(parent, x, y, w, h)                 { emit krGuiTabs(parent, x + "", y + "", w + "", h + "") }
func guiTabAdd(tabs, label)                      { emit krGuiTabAdd(tabs, label) }
func guiTabSelected(tabs)                        { emit krGuiTabSelected(tabs) }
func guiOnChange(hwnd, sinkPtr)                  { emit krGuiOnChange(hwnd, sinkPtr) }
func guiMenuBegin(window)                        { emit krGuiMenuBegin(window) }
func guiMenu(menubar, label)                     { emit krGuiMenu(menubar, label) }
func guiMenuItem(popup, label)                   { emit krGuiMenuItem(popup, label) }
func guiMenuSeparator(popup)                     { emit krGuiMenuSeparator(popup) }
func guiMenuAdd(menu, label)                     { emit krGuiMenuAdd(menu, label) }
func guiStatusBar(window)                        { emit krGuiStatusBar(window) }
func guiStatusParts(bar, widthsCsv)              { emit krGuiStatusParts(bar, widthsCsv) }
func guiStatusSet(bar, idx, text)                { emit krGuiStatusSet(bar, idx + "", text) }
func guiStatusGet(bar, idx)                      { emit krGuiStatusGet(bar, idx + "") }
func guiStatusIcon(bar, idx, iconName)           { emit krGuiStatusIcon(bar, idx + "", iconName) }
func guiStatusBgColor(bar, hex)                  { emit krGuiStatusBgColor(bar, hex) }
func guiImage(parent, path, x, y, w, h)          { emit krGuiImage(parent, path, x + "", y + "", w + "", h + "") }
func guiImageSet(image, path)                    { emit krGuiImageSet(image, path) }

// ── Layout stacks ────────────────────────────────────────────
//
// Vertical stack: pin x + width, walk widgets down the y axis.
// Horizontal stack: pin y + height, walk widgets across x.
//
// guiV* / guiH* helpers below take a stack and the per-widget cross
// size (height in V, width in H) and slot the widget in at the next
// cursor position. Each returns the same handle/id as its non-stack
// counterpart so guiOnClick / guiGetText / etc. work normally.

func guiMove(handle, x, y, w, h)                 { emit krGuiMove(handle, x + "", y + "", w + "", h + "") }
func guiDock(window)                             { emit krGuiDock(window) }
func guiDockTop(dock, hwnd, size)                { emit krGuiDockTop(dock, hwnd, size + "") }
func guiDockBottom(dock, hwnd, size)             { emit krGuiDockBottom(dock, hwnd, size + "") }
func guiDockLeft(dock, hwnd, size)               { emit krGuiDockLeft(dock, hwnd, size + "") }
func guiDockRight(dock, hwnd, size)              { emit krGuiDockRight(dock, hwnd, size + "") }
func guiDockFill(dock, hwnd)                     { emit krGuiDockFill(dock, hwnd) }
func guiDockApply(dock)                          { emit krGuiDockApply(dock) }
func guiSplitter(parent, x, y, w, h, orientation) { emit krGuiSplitter(parent, x + "", y + "", w + "", h + "", orientation) }
func guiSplitterPos(splitter)                    { emit krGuiSplitterPos(splitter) }
func guiCombo(parent, x, y, w, h)                { emit krGuiCombo(parent, x + "", y + "", w + "", h + "") }
func guiComboAdd(combo, item)                    { emit krGuiComboAdd(combo, item) }
func guiComboClear(combo)                        { emit krGuiComboClear(combo) }
func guiComboSelected(combo)                     { emit krGuiComboSelected(combo) }
func guiComboSet(combo, idx)                     { emit krGuiComboSet(combo, idx + "") }
func guiColorPicker(initialHex)                  { emit krGuiColorPicker(initialHex) }
func guiDatePicker(parent, x, y, w, h)           { emit krGuiDatePicker(parent, x + "", y + "", w + "", h + "") }
func guiDateGet(picker)                          { emit krGuiDateGet(picker) }
func guiDateSet(picker, ymd)                     { emit krGuiDateSet(picker, ymd) }
func guiScrollbar(parent, x, y, w, h, vertical)  { emit krGuiScrollbar(parent, x + "", y + "", w + "", h + "", vertical + "") }
func guiScrollbarRange(sb, lo, hi, page)         { emit krGuiScrollbarRange(sb, lo + "", hi + "", page + "") }
func guiScrollbarValue(sb)                       { emit krGuiScrollbarValue(sb) }
func guiScrollbarSet(sb, value)                  { emit krGuiScrollbarSet(sb, value + "") }
func guiVStack(parent, x, y, width, gap)         { emit krGuiVStack(parent, x + "", y + "", width + "", gap + "") }
func guiHStack(parent, x, y, height, gap)        { emit krGuiHStack(parent, x + "", y + "", height + "", gap + "") }
func guiVNext(stack, height)                     { emit krGuiVNext(stack, height + "") }
func guiHNext(stack, width)                      { emit krGuiHNext(stack, width + "") }
func guiStackParent(stack)                       { emit krGuiStackParent(stack) }
func guiStackX(stack)                            { emit krGuiStackX(stack) }
func guiStackY(stack)                            { emit krGuiStackY(stack) }
func guiStackW(stack)                            { emit krGuiStackW(stack) }
func guiStackH(stack)                            { emit krGuiStackH(stack) }
func guiVGap(stack, pixels)                      { emit krGuiStackGapAdd(stack, pixels + "") }
func guiHGap(stack, pixels)                      { emit krGuiStackGapAdd(stack, pixels + "") }

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
func guiSlider(parent, x, y, w, h)               { emit krGuiSlider(parent, x + "", y + "", w + "", h + "") }
func guiSliderRange(slider, lo, hi)              { emit krGuiSliderRange(slider, lo + "", hi + "") }
func guiSliderSet(slider, value)                 { emit krGuiSliderSet(slider, value + "") }
func guiSliderValue(slider)                      { emit krGuiSliderValue(slider) }
func guiSpinbox(parent, x, y, w, h)              { emit krGuiSpinbox(parent, x + "", y + "", w + "", h + "") }
func guiSpinboxRange(spin, lo, hi)               { emit krGuiSpinboxRange(spin, lo + "", hi + "") }
func guiSpinboxSet(spin, value)                  { emit krGuiSpinboxSet(spin, value + "") }
func guiSpinboxValue(spin)                       { emit krGuiSpinboxValue(spin) }
func guiToolbar(window)                          { emit krGuiToolbar(window) }
func guiToolButton(toolbar, label, iconName)     { emit krGuiToolButton(toolbar, label, iconName) }
func guiToolSep(toolbar)                         { emit krGuiToolSep(toolbar) }
func guiToolbarHeight(toolbar)                   { emit krGuiToolbarHeight(toolbar) }
func guiOpenFile(title, filterCsv)               { emit krGuiOpenFile(title, filterCsv) }
func guiSaveFile(title, filterCsv, defaultName)  { emit krGuiSaveFile(title, filterCsv, defaultName) }
func guiPickFolder(title)                        { emit krGuiPickFolder(title) }
func guiSetText(hwnd, text)                      { emit krGuiSetText(hwnd, text) }
func guiGetText(hwnd)                            { emit krGuiGetText(hwnd) }
func guiOnClick(hwnd, sinkPtr)                   { emit krGuiOnClick(hwnd, sinkPtr) }
func guiMessageBox(title, msg)                   { emit krGuiMessageBox(title, msg) }
func guiRun()                                    { emit krGuiRun() }
func guiQuit()                                   { emit krGuiQuit() }
