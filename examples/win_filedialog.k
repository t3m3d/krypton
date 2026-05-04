// win_filedialog.k — open file picker + read first 512 bytes of selection
//
// Compile:
//   kcc.exe --headers headers/ examples/win_filedialog.k > tmp.c
//   gcc tmp.c -o win_filedialog.exe -luser32 -lgdi32 -lcomdlg32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_filedialog.exe
//
// Click "Open File…" → standard Windows file picker. Pick any text file.
// First 512 bytes show in a multi-line read-only EDIT control below.
//
// The file-picker call goes into a `cfunc { }` helper that builds the
// OPENFILENAMEA struct and returns a clean string — much easier than
// declaring all 24 fields as a Krypton-typed struct.

import "windows.krh"
import "user32.krh"
import "gdi32.krh"
import "comdlg32.krh"

jxt {
    func krFdSetup(title)
    func krOpenFileDialog() -> char_ptr
}

cfunc {
    #include <windows.h>
    #include <commdlg.h>
    #include <stdio.h>
    #include <string.h>

    #define ID_OPEN  401
    #define ID_PATH  402
    #define ID_VIEW  403

    static const char* g_class_name = "KryptonFdWnd";
    static HWND        g_path       = NULL;
    static HWND        g_view       = NULL;

    char* krOpenFileDialog(void) {
        // Static buffer so the returned char* stays valid until next call.
        static char path[1024];
        path[0] = 0;

        OPENFILENAMEA ofn;
        memset(&ofn, 0, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.lpstrFilter =
            "Text Files\0*.txt;*.md;*.k;*.c;*.h;*.json\0All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.lpstrFile    = path;
        ofn.nMaxFile     = sizeof(path);
        ofn.Flags        = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;

        if (GetOpenFileNameA(&ofn)) {
            return path;
        }
        return "";
    }

    static void load_preview(const char* path) {
        FILE* f = fopen(path, "rb");
        if (!f) {
            SetWindowTextA(g_view, "(could not open file)");
            return;
        }
        char buf[513];
        size_t n = fread(buf, 1, 512, f);
        fclose(f);
        buf[n] = 0;
        // Replace lone \n with \r\n so the EDIT control wraps lines correctly.
        char out[1100];
        int  o = 0;
        for (size_t i = 0; i < n && o < (int)sizeof(out) - 4; i++) {
            if (buf[i] == '\n' && (i == 0 || buf[i - 1] != '\r')) {
                out[o++] = '\r';
            }
            out[o++] = buf[i];
        }
        out[o] = 0;
        SetWindowTextA(g_view, out);
    }

    static LRESULT CALLBACK krFdProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;

            CreateWindowExA(0, "BUTTON", "Open File…",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                14, 12, 130, 30,
                hwnd, (HMENU)(LONG_PTR)ID_OPEN, hInst, NULL);

            g_path = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
                160, 14, 470, 26,
                hwnd, (HMENU)(LONG_PTR)ID_PATH, hInst, NULL);

            g_view = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                WS_CHILD | WS_VISIBLE | WS_VSCROLL |
                ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY,
                14, 56, 616, 320,
                hwnd, (HMENU)(LONG_PTR)ID_VIEW, hInst, NULL);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            if (id == ID_OPEN) {
                char* p = krOpenFileDialog();
                if (p && p[0]) {
                    SetWindowTextA(g_path, p);
                    load_preview(p);
                }
                return 0;
            }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krFdSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krFdProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 660, 430,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krFdSetup("Krypton File Dialog")
    if ok == "0" {
        printErr("krFdSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("file dialog window closed")
}
