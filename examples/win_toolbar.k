// win_toolbar.k — toolbar with standard Windows icons + status bar + window icon
//
// Compile:
//   kcc.exe --headers headers/ examples/win_toolbar.k > tmp.c
//   gcc tmp.c -o win_toolbar.exe -luser32 -lgdi32 -lcomctl32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_toolbar.exe
//
// Demonstrates:
//   - `ToolbarWindow32` with standard Windows New / Open / Save / Cut /
//     Copy / Paste / Help icons (loaded via TB_LOADIMAGES with the
//     comctl32-shipped IDB_STD_SMALL_COLOR bitmap)
//   - `TB_ADDBUTTONS` with separators and BTNS_BUTTON style
//   - `TBN_DROPDOWN` / `TBN_HOTITEMCHANGE` notify-message routing
//   - LoadIconA(NULL, IDI_APPLICATION) to set the window's title-bar
//     icon (and Alt+Tab icon)
//   - Status bar tracks the most recently clicked toolbar button

import "windows.krh"
import "user32.krh"
import "gdi32.krh"
import "comctl32.krh"

jxt {
    func krToolbarSetup(title)
}

cfunc {
    #include <windows.h>
    #include <commctrl.h>
    #include <stdio.h>
    #include <string.h>

    #define ID_TOOLBAR  701
    #define ID_STATUS   702
    #define ID_EDIT     703

    // Standard small-color image indices (in the IDB_STD_SMALL_COLOR bitmap).
    #define STD_NEW       0
    #define STD_OPEN      1
    #define STD_SAVE      2
    #define STD_PRINT     3
    #define STD_PRINTPRE  4
    #define STD_PROPS     5
    #define STD_CUT       6
    #define STD_COPY      7
    #define STD_PASTE     8
    #define STD_UNDO      9
    #define STD_REDO     10
    #define STD_DELETE   11
    #define STD_HELP     14

    #define CMD_NEW    1001
    #define CMD_OPEN   1002
    #define CMD_SAVE   1003
    #define CMD_CUT    1004
    #define CMD_COPY   1005
    #define CMD_PASTE  1006
    #define CMD_HELP   1007

    static const char* g_class_name = "KryptonToolbarWnd";
    static HWND        g_toolbar    = NULL;
    static HWND        g_status     = NULL;
    static HWND        g_edit       = NULL;

    static void set_status(const char* msg) {
        SendMessageA(g_status, SB_SETTEXTA, 0, (LPARAM)msg);
    }

    static void build_toolbar(HWND parent, HINSTANCE hInst) {
        g_toolbar = CreateWindowExA(0, TOOLBARCLASSNAME, "",
            WS_CHILD | WS_VISIBLE | TBSTYLE_FLAT | TBSTYLE_TOOLTIPS | CCS_TOP,
            0, 0, 0, 0,
            parent, (HMENU)(LONG_PTR)ID_TOOLBAR, hInst, NULL);

        // Tell the toolbar what struct size we're using (required since IE 3).
        SendMessageA(g_toolbar, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);

        // Pull in the standard small-color image strip from comctl32.dll.
        TBADDBITMAP tba;
        tba.hInst = HINST_COMMCTRL;
        tba.nID   = IDB_STD_SMALL_COLOR;
        SendMessageA(g_toolbar, TB_ADDBITMAP, 15, (LPARAM)&tba);

        TBBUTTON btns[] = {
            { STD_NEW,   CMD_NEW,   TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"New"   },
            { STD_OPEN,  CMD_OPEN,  TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Open"  },
            { STD_SAVE,  CMD_SAVE,  TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Save"  },
            { 0, 0, 0, BTNS_SEP, {0,0}, 0, 0 },
            { STD_CUT,   CMD_CUT,   TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Cut"   },
            { STD_COPY,  CMD_COPY,  TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Copy"  },
            { STD_PASTE, CMD_PASTE, TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Paste" },
            { 0, 0, 0, BTNS_SEP, {0,0}, 0, 0 },
            { STD_HELP,  CMD_HELP,  TBSTATE_ENABLED, BTNS_BUTTON, {0,0}, 0, (INT_PTR)"Help"  },
        };
        SendMessageA(g_toolbar, TB_ADDBUTTONS,
                     sizeof(btns) / sizeof(btns[0]), (LPARAM)btns);
        SendMessageA(g_toolbar, TB_AUTOSIZE, 0, 0);
    }

    static LRESULT CALLBACK krToolbarProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;

            INITCOMMONCONTROLSEX icc;
            icc.dwSize = sizeof(icc);
            icc.dwICC  = ICC_BAR_CLASSES;
            InitCommonControlsEx(&icc);

            build_toolbar(hwnd, hInst);

            g_status = CreateWindowExA(0, STATUSCLASSNAME, "Ready",
                WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
                0, 0, 0, 0,
                hwnd, (HMENU)(LONG_PTR)ID_STATUS, hInst, NULL);

            g_edit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT",
                "Click a toolbar button. The status bar shows what fired.\r\n"
                "Cut / Copy / Paste actually work on this edit control.\r\n",
                WS_CHILD | WS_VISIBLE | WS_VSCROLL |
                ES_MULTILINE | ES_AUTOVSCROLL,
                0, 0, 0, 0,
                hwnd, (HMENU)(LONG_PTR)ID_EDIT, hInst, NULL);

            HFONT font = CreateFontA(
                15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN, "Consolas");
            SendMessageA(g_edit, WM_SETFONT, (WPARAM)font, TRUE);

            return 0;
        }
        if (msg == WM_SIZE) {
            // Toolbar self-positions; resize it then place edit + status.
            SendMessageA(g_toolbar, WM_SIZE, 0, 0);
            SendMessageA(g_status,  WM_SIZE, 0, 0);

            RECT tb, sb, all;
            GetClientRect(hwnd, &all);
            GetWindowRect(g_toolbar, &tb);
            GetWindowRect(g_status,  &sb);
            int tbh = tb.bottom - tb.top;
            int sbh = sb.bottom - sb.top;
            MoveWindow(g_edit, 0, tbh, all.right, all.bottom - tbh - sbh, TRUE);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            switch (id) {
                case CMD_NEW:
                    SetWindowTextA(g_edit, "");
                    set_status("New: cleared edit buffer");
                    return 0;
                case CMD_OPEN:  set_status("Open: would invoke GetOpenFileNameA");   return 0;
                case CMD_SAVE:  set_status("Save: would invoke GetSaveFileNameA");   return 0;
                case CMD_CUT:   SendMessageA(g_edit, WM_CUT,   0, 0); set_status("Cut");   return 0;
                case CMD_COPY:  SendMessageA(g_edit, WM_COPY,  0, 0); set_status("Copy");  return 0;
                case CMD_PASTE: SendMessageA(g_edit, WM_PASTE, 0, 0); set_status("Paste"); return 0;
                case CMD_HELP:
                    MessageBoxA(hwnd,
                        "Krypton Toolbar Demo\n\n"
                        "All buttons use the standard small-colour Windows "
                        "icon strip (IDB_STD_SMALL_COLOR) that comctl32 ships "
                        "with — no .ico files in the source tree.\n\n"
                        "Status bar shows which button fired. The Cut / Copy / "
                        "Paste buttons actually act on the edit control.",
                        "About",
                        MB_ICONINFORMATION | MB_OK);
                    return 0;
            }
        }
        if (msg == WM_NOTIFY) {
            LPNMHDR nm = (LPNMHDR)lp;
            if (nm->idFrom == ID_TOOLBAR && nm->code == TBN_HOTITEMCHANGE) {
                LPNMTBHOTITEM hi = (LPNMTBHOTITEM)lp;
                if (hi->dwFlags & HICF_LEAVING) {
                    set_status("Ready");
                } else {
                    char buf[64];
                    snprintf(buf, sizeof(buf), "Hot: button id %d", hi->idNew);
                    set_status(buf);
                }
            }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krToolbarSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krToolbarProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        // Title-bar / Alt-Tab icons — use stock IDI_APPLICATION so the
        // demo works without bundling its own .ico.
        wc.hIcon         = LoadIconA(NULL, IDI_APPLICATION);
        wc.hIconSm       = LoadIconA(NULL, IDI_APPLICATION);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 660, 460,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krToolbarSetup("Krypton Toolbar Demo")
    if ok == "0" {
        printErr("krToolbarSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("toolbar window closed")
}
