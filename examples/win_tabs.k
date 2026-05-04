// win_tabs.k — tab control with three pages, each demonstrating a different
// common control: slider + progress bar (Tab 1), animated progress (Tab 2),
// tree view (Tab 3).
//
// Compile:
//   kcc.exe --headers headers/ examples/win_tabs.k > tmp.c
//   gcc tmp.c -o win_tabs.exe -luser32 -lgdi32 -lcomctl32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_tabs.exe
//
// Demonstrates `SysTabControl32` (`WC_TABCONTROL`), `msctls_trackbar32`,
// `msctls_progress32`, and `SysTreeView32` (`WC_TREEVIEW`). Shows how
// to switch between tab pages by hiding/showing child-control groups
// when `TCN_SELCHANGE` fires.

import "windows.krh"
import "user32.krh"
import "gdi32.krh"
import "comctl32.krh"

jxt {
    func krTabsSetup(title)
}

cfunc {
    #include <windows.h>
    #include <commctrl.h>
    #include <stdio.h>
    #include <string.h>

    #define ID_TABS       601
    #define ID_TIMER       1
    // Tab 1 children
    #define ID_SLIDER     611
    #define ID_VAL_LABEL  612
    #define ID_BAR1       613
    // Tab 2 children
    #define ID_BAR2       621
    #define ID_BTN_START  622
    #define ID_BTN_RESET  623
    // Tab 3 children
    #define ID_TREE       631

    static const char* g_class_name = "KryptonTabsWnd";
    static HWND g_tabs        = NULL;
    static HWND g_tab1[3]     = {0};   // slider, label, bar
    static HWND g_tab2[3]     = {0};   // bar, start btn, reset btn
    static HWND g_tab3[1]     = {0};   // tree
    static int  g_active_tab  = 0;
    static int  g_animating   = 0;
    static int  g_anim_pos    = 0;

    static void show_tab(int idx) {
        int t1 = (idx == 0) ? SW_SHOW : SW_HIDE;
        int t2 = (idx == 1) ? SW_SHOW : SW_HIDE;
        int t3 = (idx == 2) ? SW_SHOW : SW_HIDE;
        for (int i = 0; i < 3; i++) ShowWindow(g_tab1[i], t1);
        for (int i = 0; i < 3; i++) ShowWindow(g_tab2[i], t2);
        for (int i = 0; i < 1; i++) ShowWindow(g_tab3[i], t3);
        g_active_tab = idx;
    }

    static void update_slider_label(void) {
        int v = (int)SendMessageA(g_tab1[0], TBM_GETPOS, 0, 0);
        char buf[64];
        snprintf(buf, sizeof(buf), "Value: %d / 100", v);
        SetWindowTextA(g_tab1[1], buf);
        SendMessageA(g_tab1[2], PBM_SETPOS, v, 0);
    }

    static void populate_tree(HWND tree) {
        TVINSERTSTRUCTA ins;

        // Root: Krypton
        memset(&ins, 0, sizeof(ins));
        ins.hParent     = TVI_ROOT;
        ins.hInsertAfter = TVI_LAST;
        ins.item.mask   = TVIF_TEXT;
        ins.item.pszText = (LPSTR)"Krypton 1.5.1";
        HTREEITEM root = (HTREEITEM)SendMessageA(tree, TVM_INSERTITEMA, 0, (LPARAM)&ins);

        const char* sections[] = {
            "Compiler",
            "Native runtime (krypton_rt.dll)",
            "Backends",
            "Headers",
            "Examples",
            NULL,
        };
        const char* compiler_kids[] = {
            "compile.k", "x64.k", "elf.k", "macho_arm64_self.k", NULL
        };
        const char* runtime_kids[] = {
            "kr_print", "kr_substring", "kr_environ", "kr_rawalloc", NULL
        };
        const char* backend_kids[] = {
            "Linux ELF (no libc)",
            "Windows PE/COFF (kernel32 only)",
            "macOS arm64 Mach-O (ad-hoc signed)", NULL
        };
        const char* header_kids[] = {
            "windows.krh", "user32.krh", "gdi32.krh",
            "comdlg32.krh", "comctl32.krh", NULL
        };
        const char* example_kids[] = {
            "win_messagebox.k", "win_hello.k", "win_counter.k",
            "win_textinput.k", "win_paint.k", "win_filedialog.k",
            "win_listview.k", "win_notepad.k", "win_tabs.k", NULL
        };
        const char** kid_lists[] = {
            compiler_kids, runtime_kids, backend_kids, header_kids, example_kids
        };

        for (int s = 0; sections[s]; s++) {
            memset(&ins, 0, sizeof(ins));
            ins.hParent      = root;
            ins.hInsertAfter = TVI_LAST;
            ins.item.mask    = TVIF_TEXT;
            ins.item.pszText = (LPSTR)sections[s];
            HTREEITEM parent = (HTREEITEM)SendMessageA(tree, TVM_INSERTITEMA, 0, (LPARAM)&ins);

            const char** kids = kid_lists[s];
            for (int k = 0; kids[k]; k++) {
                memset(&ins, 0, sizeof(ins));
                ins.hParent      = parent;
                ins.hInsertAfter = TVI_LAST;
                ins.item.mask    = TVIF_TEXT;
                ins.item.pszText = (LPSTR)kids[k];
                SendMessageA(tree, TVM_INSERTITEMA, 0, (LPARAM)&ins);
            }
        }

        // Expand the root
        SendMessageA(tree, TVM_EXPAND, TVE_EXPAND, (LPARAM)root);
    }

    static LRESULT CALLBACK krTabsProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;

            INITCOMMONCONTROLSEX icc;
            icc.dwSize = sizeof(icc);
            icc.dwICC  = ICC_TAB_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_TREEVIEW_CLASSES;
            InitCommonControlsEx(&icc);

            // Tab control fills most of the window
            g_tabs = CreateWindowExA(0, WC_TABCONTROL, "",
                WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                10, 10, 540, 360,
                hwnd, (HMENU)(LONG_PTR)ID_TABS, hInst, NULL);

            TCITEMA ti;
            memset(&ti, 0, sizeof(ti));
            ti.mask = TCIF_TEXT;

            ti.pszText = "Slider"; SendMessageA(g_tabs, TCM_INSERTITEMA, 0, (LPARAM)&ti);
            ti.pszText = "Progress"; SendMessageA(g_tabs, TCM_INSERTITEMA, 1, (LPARAM)&ti);
            ti.pszText = "Tree";    SendMessageA(g_tabs, TCM_INSERTITEMA, 2, (LPARAM)&ti);

            // Children sit inside the tab area (tab content rect).
            // For simplicity: hard-coded coords inside the tab content.
            int cx = 30, cy = 50, cw = 500, ch = 300;

            // Tab 1 — slider + label + progress mirror
            g_tab1[0] = CreateWindowExA(0, TRACKBAR_CLASS, "",
                WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_AUTOTICKS,
                cx, cy + 30, 460, 30,
                hwnd, (HMENU)(LONG_PTR)ID_SLIDER, hInst, NULL);
            SendMessageA(g_tab1[0], TBM_SETRANGE, TRUE, MAKELONG(0, 100));
            SendMessageA(g_tab1[0], TBM_SETPOS,   TRUE, 50);

            g_tab1[1] = CreateWindowExA(0, "STATIC", "Value: 50 / 100",
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                cx, cy, 200, 22,
                hwnd, (HMENU)(LONG_PTR)ID_VAL_LABEL, hInst, NULL);

            g_tab1[2] = CreateWindowExA(0, PROGRESS_CLASS, "",
                WS_CHILD | WS_VISIBLE,
                cx, cy + 80, 460, 24,
                hwnd, (HMENU)(LONG_PTR)ID_BAR1, hInst, NULL);
            SendMessageA(g_tab1[2], PBM_SETRANGE, 0, MAKELPARAM(0, 100));
            SendMessageA(g_tab1[2], PBM_SETPOS, 50, 0);

            // Tab 2 — animated progress + start / reset
            g_tab2[0] = CreateWindowExA(0, PROGRESS_CLASS, "",
                WS_CHILD | WS_VISIBLE,
                cx, cy + 30, 460, 28,
                hwnd, (HMENU)(LONG_PTR)ID_BAR2, hInst, NULL);
            SendMessageA(g_tab2[0], PBM_SETRANGE, 0, MAKELPARAM(0, 100));
            SendMessageA(g_tab2[0], PBM_SETPOS, 0, 0);

            g_tab2[1] = CreateWindowExA(0, "BUTTON", "Start",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                cx, cy + 80, 100, 32,
                hwnd, (HMENU)(LONG_PTR)ID_BTN_START, hInst, NULL);

            g_tab2[2] = CreateWindowExA(0, "BUTTON", "Reset",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                cx + 110, cy + 80, 100, 32,
                hwnd, (HMENU)(LONG_PTR)ID_BTN_RESET, hInst, NULL);

            // Tab 3 — tree view
            g_tab3[0] = CreateWindowExA(WS_EX_CLIENTEDGE, WC_TREEVIEW, "",
                WS_CHILD | WS_VISIBLE |
                TVS_HASLINES | TVS_HASBUTTONS | TVS_LINESATROOT | TVS_SHOWSELALWAYS,
                cx, cy, 460, 280,
                hwnd, (HMENU)(LONG_PTR)ID_TREE, hInst, NULL);
            populate_tree(g_tab3[0]);

            // Initial: show tab 1, hide the rest
            show_tab(0);
            return 0;
        }
        if (msg == WM_NOTIFY) {
            NMHDR* nm = (NMHDR*)lp;
            if (nm->idFrom == ID_TABS && nm->code == TCN_SELCHANGE) {
                int idx = (int)SendMessageA(g_tabs, TCM_GETCURSEL, 0, 0);
                show_tab(idx);
                return 0;
            }
        }
        if (msg == WM_HSCROLL && (HWND)lp == g_tab1[0]) {
            update_slider_label();
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            if (id == ID_BTN_START) {
                if (!g_animating) {
                    g_animating = 1;
                    SetTimer(hwnd, ID_TIMER, 30, NULL);
                    SetWindowTextA(g_tab2[1], "Pause");
                } else {
                    g_animating = 0;
                    KillTimer(hwnd, ID_TIMER);
                    SetWindowTextA(g_tab2[1], "Start");
                }
                return 0;
            }
            if (id == ID_BTN_RESET) {
                g_animating = 0;
                KillTimer(hwnd, ID_TIMER);
                SetWindowTextA(g_tab2[1], "Start");
                g_anim_pos = 0;
                SendMessageA(g_tab2[0], PBM_SETPOS, 0, 0);
                return 0;
            }
        }
        if (msg == WM_TIMER && wp == ID_TIMER) {
            g_anim_pos += 1;
            if (g_anim_pos > 100) g_anim_pos = 0;
            SendMessageA(g_tab2[0], PBM_SETPOS, g_anim_pos, 0);
            return 0;
        }
        if (msg == WM_DESTROY) {
            if (g_animating) KillTimer(hwnd, ID_TIMER);
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krTabsSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krTabsProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 580, 420,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krTabsSetup("Krypton Tab Control Demo")
    if ok == "0" {
        printErr("krTabsSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("tabs window closed")
}
