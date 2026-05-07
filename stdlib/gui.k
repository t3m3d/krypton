// stdlib/gui.k — High-level Win32 GUI library for Krypton.
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
// yet support arbitrary cross-language callbacks (Win32 WindowProc).
// Every API below is implemented in cfunc { } and exposed as a thin
// Krypton wrapper. Drop-in replaceable when native callbacks land.
//
// Build a GUI program:
//   kcc.exe my_gui.k > my_gui.c
//   gcc my_gui.c -o my_gui.exe -luser32 -lgdi32 -lcomctl32 -ldwmapi -lm -w
//
// (kbackend / kcode-win and the standard `gcc + Win32 libs` link line
// already cover this.)

module gui


jxt {
    func krGuiInit()
    func krGuiWindow(title, w, h)             -> char_ptr
    func krGuiShow(hwnd)
    func krGuiButton(parent, label, x, y, w, h) -> char_ptr
    func krGuiLabel(parent, text, x, y, w, h)  -> char_ptr
    func krGuiTextInput(parent, x, y, w, h)    -> char_ptr
    func krGuiTextArea(parent, x, y, w, h)     -> char_ptr
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
        kr_gui_create_child_w(L"STATIC", text, SS_LEFT,
                              parent_str, atoi(xs), atoi(ys), atoi(ws), atoi(hs), 0);
        return (char*)"1";
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
}


// ── Krypton public API ─────────────────────────────────────────

func guiInit()                                   { emit krGuiInit() }
func guiWindow(title, w, h)                      { emit krGuiWindow(title, w + "", h + "") }
func guiShow(hwnd)                               { emit krGuiShow(hwnd) }
func guiButton(parent, label, x, y, w, h)        { emit krGuiButton(parent, label, x + "", y + "", w + "", h + "") }
func guiLabel(parent, text, x, y, w, h)          { emit krGuiLabel(parent, text, x + "", y + "", w + "", h + "") }
func guiTextInput(parent, x, y, w, h)            { emit krGuiTextInput(parent, x + "", y + "", w + "", h + "") }
func guiTextArea(parent, x, y, w, h)             { emit krGuiTextArea(parent, x + "", y + "", w + "", h + "") }
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
