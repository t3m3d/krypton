// win_listview.k — Krypton GUI with a report-style ListView and status bar
//
// Compile:
//   kcc.exe --headers headers/ examples/win_listview.k > tmp.c
//   gcc tmp.c -o win_listview.exe -luser32 -lgdi32 -lcomctl32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_listview.exe
//
// Demonstrates two of the most-used common controls:
//
//   - SysListView32 in report (LVS_REPORT) mode with three columns
//     (Name / Kind / Size) and a few sample rows. Click a row to
//     update the status bar with the selection. Click a column header
//     to sort by that column.
//   - msctls_statusbar32 with two panes (selection summary + row count)
//
// The five-part GUI skeleton is unchanged from win_hello / win_counter:
// WindowProc + class registration + setup live in cfunc; the message
// pump is pure Krypton.

import "windows.krh"
import "user32.krh"
import "gdi32.krh"
import "comctl32.krh"

jxt {
    func krLvSetup(title)
}

cfunc {
    #include <windows.h>
    #include <commctrl.h>
    #include <stdio.h>
    #include <string.h>
    #include <stdlib.h>

    #define ID_LIST   501
    #define ID_STATUS 502

    static const char* g_class_name = "KryptonListViewWnd";
    static HWND        g_list       = NULL;
    static HWND        g_status     = NULL;
    static int         g_sort_col   = -1;
    static int         g_sort_asc   = 1;

    typedef struct { const char* name; const char* kind; int size; } Row;

    static Row g_rows[] = {
        { "compile.k",       "Krypton source",   168432 },
        { "x64.k",           "Krypton source",   148912 },
        { "elf.k",           "Krypton source",    96104 },
        { "krypton_rt.dll",  "Runtime DLL",       10240 },
        { "kcc.exe",         "Compiler",         827931 },
        { "kcc-x64.exe",     "Compiler (alt)",   827931 },
        { "windows.krh",     "Header binding",     5128 },
        { "user32.krh",      "Header binding",     2944 },
        { "gdi32.krh",       "Header binding",     1872 },
        { "comdlg32.krh",    "Header binding",     1024 },
        { "comctl32.krh",    "Header binding",     2240 },
        { "win_hello.k",     "GUI example",        2880 },
        { "win_counter.k",   "GUI example",        4096 },
        { "win_paint.k",     "GUI example",        7424 },
        { "win_listview.k",  "GUI example",        6912 },
    };
    #define ROW_COUNT  ((int)(sizeof(g_rows)/sizeof(g_rows[0])))

    static int CALLBACK compare_rows(LPARAM la, LPARAM lb, LPARAM lpsort) {
        int col  = (int)(lpsort & 0xFFFF);
        int asc  = (int)((lpsort >> 16) & 1) ? 1 : -1;
        const Row* a = &g_rows[la];
        const Row* b = &g_rows[lb];
        int r = 0;
        if (col == 0) r = strcmp(a->name, b->name);
        else if (col == 1) r = strcmp(a->kind, b->kind);
        else if (col == 2) r = (a->size > b->size) - (a->size < b->size);
        return asc * r;
    }

    static void update_status(void) {
        int n = ListView_GetItemCount(g_list);
        int sel = ListView_GetNextItem(g_list, -1, LVNI_SELECTED);
        char buf[256];
        if (sel >= 0) {
            LVITEMA item;
            char nameBuf[128];
            memset(&item, 0, sizeof(item));
            item.mask        = LVIF_TEXT | LVIF_PARAM;
            item.iItem       = sel;
            item.iSubItem    = 0;
            item.pszText     = nameBuf;
            item.cchTextMax  = sizeof(nameBuf);
            ListView_GetItem(g_list, &item);
            int origIdx = (int)item.lParam;
            snprintf(buf, sizeof(buf), "Selected: %s  (%d bytes)",
                     g_rows[origIdx].name, g_rows[origIdx].size);
        } else {
            snprintf(buf, sizeof(buf), "No selection");
        }
        SendMessageA(g_status, SB_SETTEXTA, 0, (LPARAM)buf);

        char countBuf[64];
        snprintf(countBuf, sizeof(countBuf), "Rows: %d", n);
        SendMessageA(g_status, SB_SETTEXTA, 1, (LPARAM)countBuf);
    }

    static void add_column(int idx, const char* title, int width) {
        LVCOLUMNA col;
        memset(&col, 0, sizeof(col));
        col.mask     = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
        col.iSubItem = idx;
        col.pszText  = (LPSTR)title;
        col.cx       = width;
        SendMessageA(g_list, LVM_INSERTCOLUMNA, idx, (LPARAM)&col);
    }

    static void populate_list(void) {
        for (int i = 0; i < ROW_COUNT; i++) {
            LVITEMA item;
            memset(&item, 0, sizeof(item));
            item.mask     = LVIF_TEXT | LVIF_PARAM;
            item.iItem    = i;
            item.iSubItem = 0;
            item.pszText  = (LPSTR)g_rows[i].name;
            item.lParam   = (LPARAM)i;
            int idx = (int)SendMessageA(g_list, LVM_INSERTITEMA, 0, (LPARAM)&item);

            ListView_SetItemText(g_list, idx, 1, (LPSTR)g_rows[i].kind);

            char szbuf[32];
            snprintf(szbuf, sizeof(szbuf), "%d", g_rows[i].size);
            ListView_SetItemText(g_list, idx, 2, szbuf);
        }
    }

    static void resize_status(HWND hwnd) {
        SendMessageA(g_status, WM_SIZE, 0, 0);
        // Two panes: name pane (everything but last 100px) + count pane.
        RECT rc;
        GetClientRect(hwnd, &rc);
        int parts[2] = { rc.right - 110, -1 };
        SendMessageA(g_status, SB_SETPARTS, 2, (LPARAM)parts);
    }

    static LRESULT CALLBACK krLvProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;

            INITCOMMONCONTROLSEX icc;
            icc.dwSize = sizeof(icc);
            icc.dwICC  = ICC_LISTVIEW_CLASSES | ICC_BAR_CLASSES;
            InitCommonControlsEx(&icc);

            g_list = CreateWindowExA(WS_EX_CLIENTEDGE, WC_LISTVIEW, "",
                WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SHOWSELALWAYS,
                0, 0, 600, 400,
                hwnd, (HMENU)(LONG_PTR)ID_LIST, hInst, NULL);

            ListView_SetExtendedListViewStyle(g_list,
                LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_DOUBLEBUFFER);

            add_column(0, "Name", 220);
            add_column(1, "Kind", 180);
            add_column(2, "Size (bytes)", 120);
            populate_list();

            g_status = CreateWindowExA(0, STATUSCLASSNAME, "Ready",
                WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
                0, 0, 0, 0,
                hwnd, (HMENU)(LONG_PTR)ID_STATUS, hInst, NULL);
            resize_status(hwnd);
            update_status();
            return 0;
        }
        if (msg == WM_SIZE) {
            RECT rc;
            GetClientRect(hwnd, &rc);
            // Status bar self-positions; resize listview to fill above it.
            RECT sb;
            GetWindowRect(g_status, &sb);
            int sbh = sb.bottom - sb.top;
            MoveWindow(g_list, 0, 0, rc.right, rc.bottom - sbh, TRUE);
            resize_status(hwnd);
            return 0;
        }
        if (msg == WM_NOTIFY) {
            NMHDR* nm = (NMHDR*)lp;
            if (nm->idFrom == ID_LIST) {
                if (nm->code == LVN_ITEMCHANGED) {
                    update_status();
                    return 0;
                }
                if (nm->code == LVN_COLUMNCLICK) {
                    NMLISTVIEW* nlv = (NMLISTVIEW*)lp;
                    if (g_sort_col == nlv->iSubItem) {
                        g_sort_asc = !g_sort_asc;
                    } else {
                        g_sort_col = nlv->iSubItem;
                        g_sort_asc = 1;
                    }
                    LPARAM key = (LPARAM)((g_sort_asc ? 1 : 0) << 16) | (LPARAM)nlv->iSubItem;
                    ListView_SortItems(g_list, compare_rows, key);
                    return 0;
                }
            }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krLvSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krLvProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 620, 460,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krLvSetup("Krypton ListView Demo")
    if ok == "0" {
        printErr("krLvSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("listview window closed")
}
