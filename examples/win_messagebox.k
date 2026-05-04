// win_messagebox.k — pop a Windows dialog from Krypton
//
// Compile:
//   kcc.exe --headers headers/ examples/win_messagebox.k > tmp.c
//   gcc tmp.c -o win_messagebox.exe -luser32 -lm -w
// Run:
//   .\win_messagebox.exe
//
// Smallest possible GUI program in Krypton. No window class, no message pump,
// no WindowProc — MessageBoxA blocks until the user clicks OK.

import "user32.krh"

just run {
    // MB_OK | MB_ICONINFORMATION = 0 | 0x40 = 64
    MessageBoxA("0", "Hello from Krypton!", "Krypton GUI", "64")
    kp("dialog dismissed")
}
