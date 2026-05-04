// win_paint.k — drag-to-draw paint canvas in Krypton
//
// Compile:
//   kcc.exe --headers headers/ examples/win_paint.k > tmp.c
//   gcc tmp.c -o win_paint.exe -luser32 -lgdi32 -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
// Run:
//   .\win_paint.exe
//
// Hold left mouse button and drag across the canvas — leaves a coloured
// trail. Right-click to clear. Top toolbar has "Red", "Green", "Blue",
// "Black" buttons that switch the brush colour.
//
// Demonstrates:
//   - WM_LBUTTONDOWN / WM_MOUSEMOVE / WM_LBUTTONUP captured input
//   - SetCapture / ReleaseCapture for off-window dragging
//   - Persistent drawing via off-screen bitmap (compatible DC) so resizes
//     don't wipe the canvas
//   - GDI: CreatePen + CreateSolidBrush + LineTo / FillRect

import "windows.krh"
import "user32.krh"
import "gdi32.krh"

jxt {
    func krPaintSetup(title)
}

cfunc {
    #include <windows.h>
    #include <stdio.h>

    #define ID_RED   301
    #define ID_GREEN 302
    #define ID_BLUE  303
    #define ID_BLACK 304

    #define TOOLBAR_H 40

    static const char* g_class_name = "KryptonPaintWnd";
    static HBITMAP     g_canvas     = NULL;     // persistent off-screen bitmap
    static HDC         g_canvas_dc  = NULL;     // memory DC bound to g_canvas
    static int         g_canvas_w   = 0;
    static int         g_canvas_h   = 0;
    static COLORREF    g_color      = RGB(0, 0, 0);
    static int         g_drawing    = 0;
    static int         g_last_x     = 0;
    static int         g_last_y     = 0;

    static void ensure_canvas(HWND hwnd) {
        RECT rc;
        GetClientRect(hwnd, &rc);
        int w = rc.right - rc.left;
        int h = rc.bottom - rc.top - TOOLBAR_H;
        if (w == g_canvas_w && h == g_canvas_h && g_canvas) return;

        HDC win_dc = GetDC(hwnd);
        HBITMAP newbm = CreateCompatibleBitmap(win_dc, w, h);
        HDC newdc = CreateCompatibleDC(win_dc);
        SelectObject(newdc, newbm);

        // White background
        RECT all = {0, 0, w, h};
        HBRUSH wb = CreateSolidBrush(RGB(255, 255, 255));
        FillRect(newdc, &all, wb);
        DeleteObject(wb);

        // Copy old canvas if it existed
        if (g_canvas_dc) {
            BitBlt(newdc, 0, 0, g_canvas_w, g_canvas_h, g_canvas_dc, 0, 0, SRCCOPY);
            DeleteDC(g_canvas_dc);
            DeleteObject(g_canvas);
        }

        g_canvas    = newbm;
        g_canvas_dc = newdc;
        g_canvas_w  = w;
        g_canvas_h  = h;
        ReleaseDC(hwnd, win_dc);
    }

    static void clear_canvas(HWND hwnd) {
        if (!g_canvas_dc) return;
        RECT all = {0, 0, g_canvas_w, g_canvas_h};
        HBRUSH wb = CreateSolidBrush(RGB(255, 255, 255));
        FillRect(g_canvas_dc, &all, wb);
        DeleteObject(wb);
        InvalidateRect(hwnd, NULL, FALSE);
    }

    static void stroke(int x0, int y0, int x1, int y1) {
        if (!g_canvas_dc) return;
        HPEN pen = CreatePen(PS_SOLID, 3, g_color);
        HPEN old = (HPEN)SelectObject(g_canvas_dc, pen);
        MoveToEx(g_canvas_dc, x0, y0, NULL);
        LineTo(g_canvas_dc, x1, y1);
        SelectObject(g_canvas_dc, old);
        DeleteObject(pen);
    }

    static LRESULT CALLBACK krPaintProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (msg == WM_CREATE) {
            HINSTANCE hInst = ((LPCREATESTRUCTA)lp)->hInstance;
            CreateWindowExA(0, "BUTTON", "Red",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 8, 6, 70, 28,
                hwnd, (HMENU)(LONG_PTR)ID_RED, hInst, NULL);
            CreateWindowExA(0, "BUTTON", "Green",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 84, 6, 70, 28,
                hwnd, (HMENU)(LONG_PTR)ID_GREEN, hInst, NULL);
            CreateWindowExA(0, "BUTTON", "Blue",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 160, 6, 70, 28,
                hwnd, (HMENU)(LONG_PTR)ID_BLUE, hInst, NULL);
            CreateWindowExA(0, "BUTTON", "Black",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 236, 6, 70, 28,
                hwnd, (HMENU)(LONG_PTR)ID_BLACK, hInst, NULL);
            return 0;
        }
        if (msg == WM_COMMAND) {
            int id = LOWORD(wp);
            if (id == ID_RED)   { g_color = RGB(220, 60, 60);   return 0; }
            if (id == ID_GREEN) { g_color = RGB(60, 180, 80);   return 0; }
            if (id == ID_BLUE)  { g_color = RGB(60, 110, 220);  return 0; }
            if (id == ID_BLACK) { g_color = RGB(0, 0, 0);       return 0; }
        }
        if (msg == WM_SIZE) {
            ensure_canvas(hwnd);
            return 0;
        }
        if (msg == WM_LBUTTONDOWN) {
            ensure_canvas(hwnd);
            int x = (int)LOWORD(lp);
            int y = (int)HIWORD(lp) - TOOLBAR_H;
            if (y < 0) return 0;
            g_drawing = 1;
            g_last_x  = x;
            g_last_y  = y;
            SetCapture(hwnd);
            return 0;
        }
        if (msg == WM_MOUSEMOVE && g_drawing) {
            int x = (int)LOWORD(lp);
            int y = (int)HIWORD(lp) - TOOLBAR_H;
            stroke(g_last_x, g_last_y, x, y);
            g_last_x = x;
            g_last_y = y;
            RECT inv = {0, TOOLBAR_H, g_canvas_w, g_canvas_h + TOOLBAR_H};
            InvalidateRect(hwnd, &inv, FALSE);
            return 0;
        }
        if (msg == WM_LBUTTONUP) {
            g_drawing = 0;
            ReleaseCapture();
            return 0;
        }
        if (msg == WM_RBUTTONDOWN) {
            clear_canvas(hwnd);
            return 0;
        }
        if (msg == WM_PAINT) {
            ensure_canvas(hwnd);
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            // Toolbar background
            RECT tb;
            GetClientRect(hwnd, &tb);
            tb.bottom = TOOLBAR_H;
            HBRUSH gb = CreateSolidBrush(RGB(235, 235, 240));
            FillRect(hdc, &tb, gb);
            DeleteObject(gb);
            // Blit canvas under the toolbar
            if (g_canvas_dc) {
                BitBlt(hdc, 0, TOOLBAR_H, g_canvas_w, g_canvas_h,
                       g_canvas_dc, 0, 0, SRCCOPY);
            }
            EndPaint(hwnd, &ps);
            return 0;
        }
        if (msg == WM_DESTROY) {
            if (g_canvas_dc) { DeleteDC(g_canvas_dc); g_canvas_dc = NULL; }
            if (g_canvas)    { DeleteObject(g_canvas); g_canvas = NULL; }
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProcA(hwnd, msg, wp, lp);
    }

    char* krPaintSetup(char* title) {
        HINSTANCE hInst = GetModuleHandleA(NULL);

        WNDCLASSEXA wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = krPaintProc;
        wc.hInstance     = hInst;
        wc.lpszClassName = g_class_name;
        wc.hCursor       = LoadCursorA(NULL, IDC_CROSS);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        RegisterClassExA(&wc);

        HWND hwnd = CreateWindowExA(
            0, g_class_name, title,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT, 720, 520,
            NULL, NULL, hInst, NULL
        );
        if (!hwnd) return (char*)"0";

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        return (char*)"1";
    }
}

just run {
    let ok = krPaintSetup("Krypton Paint")
    if ok == "0" {
        printErr("krPaintSetup failed")
        emit 1
    }

    let msg = structNew("MSG")
    let r = GetMessageA(msg, "0", "0", "0")
    while r != "0" {
        TranslateMessage(msg)
        DispatchMessageA(msg)
        r = GetMessageA(msg, "0", "0", "0")
    }

    kp("paint window closed")
}
