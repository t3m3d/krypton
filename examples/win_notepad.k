// win_notepad.k — minimal text editor with a File / Edit menu bar
//
// Compile:
//   kcc.exe --headers headers/ examples/win_notepad.k > tmp.c
//   gcc tmp.c -o win_notepad.exe -luser32 -lgdi32 -lcomdlg32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_notepad.exe
//
// First Krypton GUI program with a real menu bar. The window has:
//
//   File menu:   New, Open…, Save As…, Exit
//   Edit menu:   Cut, Copy, Paste, Select All, Clear
//   Help menu:   About
//
// File>Open uses GetOpenFileNameA from comdlg32.krh (same pattern as
// win_filedialog.k). The text body is a multi-line EDIT control with
// scrollbars; menu commands route through the standard edit-control
// messages (WM_CUT / WM_COPY / WM_PASTE / EM_SETSEL).

import "windows.krh"
import "user32.krh"
import "gdi32.krh"
import "comdlg32.krh"

jxt {
    func krNotepadSetup(title)
}

cfunc {
    #include <windows.h>
    #include <commdlg.h>
    #include <stdio.h>
    #include <string.h>

    #define ID_EDIT          1001
    #define IDM_FILE_NEW     2001
    #define IDM_FILE_OPEN    2002
    #define IDM_FILE_SAVEAS  2003
    #define IDM_FILE_EXIT    2099
    #define IDM_EDIT_CUT     3001
    #define IDM_EDIT_COPY    3002
    #define IDM_EDIT_PASTE   3003
    #define IDM_EDIT_SELALL  3004
    #define IDM_EDIT_CLEAR   3005
    #define IDM_HELP_ABOUT   4001

    static const char* g_class_name = "KryptonNotepadWnd";
    static HWND        g_edit       = NULL;
    static char        g_path[1024] = "";

    static HMENU build_menu_bar(void) {
        HMENU bar = CreateMenu();

        HMENU file = CreatePopupMenu();
        AppendMenuA(file, MF_STRING, IDM_FILE_NEW,    "&New\tCtrl+N");
        AppendMenuA(file, MF_STRING, IDM_FILE_OPEN,   "&Open...\tCtrl+O");
        AppendMenuA(file, MF_STRING, IDM_FILE_SAVEAS, "Save &As...\tCtrl+S");
        AppendMenuA(file, MF_SEPARATOR, 0, NULL);
        AppendMenuA(file, MF_STRING, IDM_FILE_EXIT,   "E&xit");
        AppendMenuA(bar, MF_POPUP, (UINT_PTR)file, "&File");

        HMENU edit = CreatePopupMenu();
        AppendMenuA(edit, MF_STRING, IDM_EDIT_CUT,    "Cu&t\tCtrl+X");
        AppendMenuA(edit, MF_STRING, IDM_EDIT_COPY,   "&Copy\tCtrl+C");
        AppendMenuA(edit, MF_STRING, IDM_EDIT_PASTE,  "&Paste\tCtrl+V");
        AppendMenuA(edit, MF_SEPARATOR, 0, NULL);
        AppendMenuA(edit, MF_STRING, IDM_EDIT_SELALL, "Select &All\tCtrl+A");
        AppendMenuA(edit, MF_STRING, IDM_EDIT_CLEAR,  "C&lear");
        AppendMenuA(bar, MF_POPUP, (UINT_PTR)edit, "&Edit");

        HMENU help = CreatePopupMenu();
        AppendMenuA(help, MF_STRING, IDM_HELP_ABOUT, "&About");
        AppendMenuA(bar, MF_POPUP, (UINT_PTR)help, "&Help");

        return bar;
    }

    static void update_title(HWND hwnd) {
        char title[1100];
        if (g_path[0]) {
            // strip path, just show file name in title
            const char* base = g_path;
            for (const char* p = g_path; *p; p++) {
                if (*p == '\\' || *p == '/') base = p + 1;
            }
            snprintf(title, sizeof(title), "%s — Krypton Notepad", base);
        } else {
            snprintf(title, sizeof(title), "Untitled — Krypton Notepad");
        }
        SetWindowTextA(hwnd, title);
    }

    static void load_file_into_edit(const char* path) {
        FILE* f = fopen(path, "rb");
        if (!f) {
            MessageBoxA(NULL, "Could not open the selected file.",
                        "Krypton Notepad", MB_ICONERROR | MB_OK);
            return;
        }
        fseek(f, 0, SEEK_END);
        long n = ftell(f);
        if (n < 0) n = 0;
        if (n > 1024 * 1024) n = 1024 * 1024;   // cap at 1 MB
        fseek(f, 0, SEEK_SET);
        char* buf = (char*)malloc(n + 1);
        if (!buf) { fclose(f); return; }
        size_t r = fread(buf, 1, n, f);
        fclose(f);
        buf[r] = 0;

        // Convert lone \n to \r\n so the EDIT control wraps correctly.
        char* out = (char*)malloc(r * 2 + 1);
        if (!out) { free(buf); return; }
        size_t o = 0;
        for (size_t i = 0; i < r; i++) {
            if (buf[i] == '\n' && (i == 0 || buf[i - 1] != '\r')) {
                out[o++] = '\r';
            }
            out[o++] = buf[i];
        }
        out[o] = 0;
        SetWindowTextA(g_edit, out);
        free(out);
        free(buf);
    }

    static void save_edit_to_file(const char* path) {
        int n = GetWindowTextLengthA(g_edit);
        char* buf = (char*)malloc(n + 1);
        if (!buf) return;
        GetWindowTextA(g_edit, buf, n + 1);
        FILE* f = fopen(path, "wb");
        if (!f) {
            free(buf);
            MessageBoxA(NULL, "Could not write the selected file.",
                        "Krypton Notepad", MB_ICONERROR | MB_OK);
            return;
        }
        fwrite(buf, 1, n, f);
        fclose(f);
        free(buf);
    }

    static int do_open_dialog(HWND hwnd) {
        char path[1024] = {0};
        OPENFILENAMEA ofn;
        memset(&ofn, 0, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner   = hwnd;
        ofn.lpstrFilter =
            "Text Files\0*.txt;*.md;*.k;*.c;*.h\0All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.lpstrFile    = path;
        ofn.nMaxFile     = sizeof(path);
        ofn.Flags        = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;

        if (GetOpenFileNameA(&ofn)) {
            strncpy(g_path, path, sizeof(g_path) - 1);
            g_path[sizeof(g_path) - 1] = 0;
            load_file_into_edit(g_path);
            update_title(hwnd);
            return 1;
        }
        return 0;
    }

    static int do_saveas_dialog(HWND hwnd) {
        char path[1024] = {0};
        if (g_path[0]) strncpy(path, g_path, sizeof(path) - 1);

        OPENFILENAMEA ofn;
        memset(&ofn, 0, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner   = hwnd;
        ofn.lpstrFilter = "Text Files\0*.txt\0All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.lpstrFile    = path;
        ofn.nMaxFile     = sizeof(path);
        ofn.Flags        = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        ofn.lpstrDefExt  = "txt";

        if (GetSaveFileNameA(&ofn)) {
            strncpy(g_path, path, sizeof(g_path) - 1);
            g_path[sizeof(g_path) - 1] = 0;
            save_edit_to_file(g_path);
            update_title(hwnd);
            return 1;
        }
        return 0;
    }

    static LRESULT CALLBACK krNotepadProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;
            g_edit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL |
                ES_MULTILINE | ES_AUTOHSCROLL | ES_AUTOVSCROLL | ES_NOHIDESEL,
                0, 0, 600, 400,
                hwnd, (HMENU)(LONG_PTR)ID_EDIT, hInst, NULL);

            HFONT font = CreateFontA(
                16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN, "Consolas");
            SendMessageA(g_edit, WM_SETFONT, (WPARAM)font, TRUE);
            return 0;
        }
        if (msg == WM_SIZE) {
            int w = LOWORD(lp);
            int h = HIWORD(lp);
            MoveWindow(g_edit, 0, 0, w, h, TRUE);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            switch (id) {
                case IDM_FILE_NEW:
                    SetWindowTextA(g_edit, "");
                    g_path[0] = 0;
                    update_title(hwnd);
                    return 0;
                case IDM_FILE_OPEN:
                    do_open_dialog(hwnd);
                    return 0;
                case IDM_FILE_SAVEAS:
                    do_saveas_dialog(hwnd);
                    return 0;
                case IDM_FILE_EXIT:
                    PostMessageA(hwnd, WM_CLOSE, 0, 0);
                    return 0;
                case IDM_EDIT_CUT:
                    SendMessageA(g_edit, WM_CUT, 0, 0);
                    return 0;
                case IDM_EDIT_COPY:
                    SendMessageA(g_edit, WM_COPY, 0, 0);
                    return 0;
                case IDM_EDIT_PASTE:
                    SendMessageA(g_edit, WM_PASTE, 0, 0);
                    return 0;
                case IDM_EDIT_SELALL:
                    SendMessageA(g_edit, EM_SETSEL, 0, -1);
                    return 0;
                case IDM_EDIT_CLEAR:
                    SetWindowTextA(g_edit, "");
                    return 0;
                case IDM_HELP_ABOUT:
                    MessageBoxA(hwnd,
                        "Krypton Notepad\nA tiny text editor written in Krypton.\n\n"
                        "Demonstrates menu bars, multi-line EDIT controls, "
                        "and comdlg32 file pickers.",
                        "About Krypton Notepad",
                        MB_ICONINFORMATION | MB_OK);
                    return 0;
            }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krNotepadSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krNotepadProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HMENU bar = build_menu_bar();

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 720, 520,
            NULL, bar, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        update_title(hwnd);
        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krNotepadSetup("Krypton Notepad")
    if ok == "0" {
        printErr("krNotepadSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("notepad window closed")
}
