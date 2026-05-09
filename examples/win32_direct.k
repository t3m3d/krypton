// 2.0-alpha-3: direct Win32 calls without cfunc wrappers.
//
// Krypton stores all values as char* pointers. Win32 functions like
// Sleep(DWORD ms) expect an int in RCX/RDX/R8/R9 — a string pointer
// gets misread as a huge integer. Win32 fns that RETURN ints (like
// GetTickCount → DWORD) hand back a raw int in RAX which Krypton
// would treat as a pointer → segfault on next use.
//
// x64.k now atoi's int args at the call site (win32IntArgs table) and
// itoa's int returns to char* (win32IntReturns table). `Sleep(500)`
// and `GetTickCount()` work directly — no cfunc wrapper.

import "head:process"

just run {
    let t0 = GetTickCount()
    print("t0=" + t0 + " ms")

    print("Sleeping 750 ms...")
    Sleep(750)

    let t1 = GetTickCount()
    print("t1=" + t1 + " ms")

    let dt = toInt(t1) - toInt(t0)
    print("elapsed=" + dt + " ms")
    print("pid=" + GetCurrentProcessId())
}
