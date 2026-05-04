// win_counter.k — Krypton GUI app with buttons, a label, and click handlers
//
// Compile:
//   kcc.exe --headers headers/ examples/win_counter.k > tmp.c
//   gcc tmp.c -o win_counter.exe -luser32 -lgdi32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_counter.exe
//
// Demonstrates:
//   - Three child windows: a STATIC label + two BUTTONs ("+" and "−")
//   - WM_COMMAND dispatch by control ID
//   - SetWindowTextA to live-update the label
//   - InvalidateRect + UpdateWindow to force a clean repaint
//
// The full state machine + WindowProc lives in cfunc (Tier 3 / native
// callbacks would let it move to Krypton). The Krypton side is the
// message pump driver — same pattern as win_hello.k.

import "windows.krh"
import "user32.krh"
import "gdi32.krh"

jxt {
    func krCounterSetup(title)
}

cfunc {
    #include <windows.h>
    #include <stdio.h>

    #define ID_LABEL  101
    #define ID_INC    102
    #define ID_DEC    103

    static const char* g_class_name = "KryptonCounterWnd";
    static HWND        g_label      = NULL;
    static int         g_count      = 0;

    static void update_label(void) {
        char buf[64];
        snprintf(buf, sizeof(buf), "Count: %d", g_count);
        SetWindowTextA(g_label, buf);
    }

    static LRESULT CALLBACK krCounterProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;
            g_label = CreateWindowExA(0, "STATIC", "Count: 0",
                WS_CHILD | WS_VISIBLE | SS_CENTER,
                40, 30, 240, 32,
                hwnd, (HMENU)(LONG_PTR)ID_LABEL, hInst, NULL);

            CreateWindowExA(0, "BUTTON", "−",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                40, 80, 100, 36,
                hwnd, (HMENU)(LONG_PTR)ID_DEC, hInst, NULL);

            CreateWindowExA(0, "BUTTON", "+",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                180, 80, 100, 36,
                hwnd, (HMENU)(LONG_PTR)ID_INC, hInst, NULL);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            if (id == ID_INC) { g_count++; update_label(); return 0; }
            if (id == ID_DEC) { g_count--; update_label(); return 0; }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krCounterSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krCounterProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 340, 180,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krCounterSetup("Krypton Counter")
    if ok == "0" {
        printErr("krCounterSetup failed")
        emit 1
    }

    // Same pure-Krypton message pump as win_hello.k
    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("counter window closed")
}
