// win_hello.k — first Krypton GUI program with a real window
//
// Compile:
//   kcc.exe --headers headers/ examples/win_hello.k > tmp.c
//   gcc tmp.c -o win_hello.exe -luser32 -lgdi32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
//
// (The psapi/pdh/shell32/advapi32 flags are pulled in transitively by
// windows.krh declaring functions from those DLLs — they need link-time
// resolution even if our program doesn't call them.)
//
// Run: .\win_hello.exe
//
// Demonstrates the Tier 2 GUI bindings end-to-end. The split:
//   - WindowProc + class registration + window creation: cfunc { } block
//     (because C callbacks aren't yet supported by the native pipeline,
//     Tier 3 work — see krypton-lang.org roadmap)
//   - Message loop: pure Krypton, calling GetMessageA / TranslateMessage /
//     DispatchMessageA from user32.krh
//   - Quit handling: PostQuitMessage in the WindowProc (C side) makes
//     GetMessageA return 0 and the Krypton loop exits
//
// As Tier 3 lands and the native pipeline can emit WindowProc-shaped
// callbacks directly, the cfunc block gets smaller and more lives in
// Krypton proper.

import "windows.krh"
import "user32.krh"
import "gdi32.krh"

jxt {
    func krWinSetup(title)
}

cfunc {
    #include <windows.h>

    static const char* g_class_name = "KryptonHelloWnd";

    static LRESULT CALLBACK krWinProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_DESTROY) {
            PostQuitMessage(0);
            return 0;
        }
        if (msg == WM_PAINT) {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            const char* line1 = "Hello from Krypton!";
            const char* line2 = "Window class registered, message pump in .k";
            SetTextColor(hdc, RGB(80, 200, 120));
            SetBkMode(hdc, TRANSPARENT);
            TextOutA(hdc, 30, 30, line1, (int)strlen(line1));
            TextOutA(hdc, 30, 60, line2, (int)strlen(line2));
            EndPaint(hwnd, &ps);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krWinSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krWinProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 520, 280,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krWinSetup("Krypton 1.5.1 — Hello GUI")
    if ok == "0" {
        printErr("krWinSetup failed")
        emit 1
    }

    // Pure-Krypton message pump using the user32.krh bindings.
    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("window closed cleanly")
}
