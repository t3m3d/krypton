// win_textinput.k — text input field + button + live label
//
// Compile:
//   kcc.exe --headers headers/ examples/win_textinput.k > tmp.c
//   gcc tmp.c -o win_textinput.exe -luser32 -lgdi32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_textinput.exe
//
// Demonstrates the EDIT control (single-line text entry). Type something,
// click "Reverse" → label shows it reversed. Click "Upper" → uppercased.
// Click "Clear" → wipes the input. The string transforms run in C inside
// the WindowProc; the message pump is pure Krypton (same pattern as
// win_hello / win_counter).

import "windows.krh"
import "user32.krh"
import "gdi32.krh"

jxt {
    func krInputSetup(title)
}

cfunc {
    #include <windows.h>
    #include <stdio.h>
    #include <string.h>
    #include <ctype.h>

    #define ID_INPUT   201
    #define ID_LABEL   202
    #define ID_REVERSE 203
    #define ID_UPPER   204
    #define ID_CLEAR   205

    static const char* g_class_name = "KryptonInputWnd";
    static HWND        g_input      = NULL;
    static HWND        g_label      = NULL;

    static void show_result(const char* msg, const char* val) {
        char buf[1024];
        snprintf(buf, sizeof(buf), "%s: %s", msg, val);
        SetWindowTextA(g_label, buf);
    }

    static LRESULT CALLBACK krInputProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;

            CreateWindowExA(0, "STATIC", "Type something:",
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 18, 380, 20,
                hwnd, NULL, hInst, NULL);

            g_input = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                20, 42, 380, 26,
                hwnd, (HMENU)(LONG_PTR)ID_INPUT, hInst, NULL);

            CreateWindowExA(0, "BUTTON", "Reverse",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                20, 80, 110, 32,
                hwnd, (HMENU)(LONG_PTR)ID_REVERSE, hInst, NULL);

            CreateWindowExA(0, "BUTTON", "Upper",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                145, 80, 110, 32,
                hwnd, (HMENU)(LONG_PTR)ID_UPPER, hInst, NULL);

            CreateWindowExA(0, "BUTTON", "Clear",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                270, 80, 110, 32,
                hwnd, (HMENU)(LONG_PTR)ID_CLEAR, hInst, NULL);

            g_label = CreateWindowExA(0, "STATIC", "(no result yet)",
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 130, 380, 50,
                hwnd, (HMENU)(LONG_PTR)ID_LABEL, hInst, NULL);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            char text[512] = {0};
            GetWindowTextA(g_input, text, sizeof(text) - 1);

            if (id == ID_REVERSE) {
                int n = (int)strlen(text);
                char rev[512];
                for (int i = 0; i < n; i++) rev[i] = text[n - 1 - i];
                rev[n] = 0;
                show_result("Reversed", rev);
                return 0;
            }
            if (id == ID_UPPER) {
                for (int i = 0; text[i]; i++) text[i] = (char)toupper((unsigned char)text[i]);
                show_result("Uppercased", text);
                return 0;
            }
            if (id == ID_CLEAR) {
                SetWindowTextA(g_input, "");
                SetWindowTextA(g_label, "(cleared)");
                SetFocus(g_input);
                return 0;
            }
        }
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krInputSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krInputProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 440, 230,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krInputSetup("Krypton Text Input")
    if ok == "0" {
        printErr("krInputSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("input window closed")
}
