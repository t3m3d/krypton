// 2.0-alpha-3: direct Win32 calls without cfunc wrappers.
//
// Krypton stores all values as char* pointers. Win32 functions like
// Sleep(DWORD ms) expect an int in RCX/RDX/R8/R9 — a string pointer
// gets misread as a huge integer. Win32 fns that RETURN ints (like
// GetTickCount → DWORD) hand back a raw int in RAX which Krypton
// would treat as a pointer → segfault on next use.
//
// x64.k atoi's int args (win32IntArgs table) and itoa's int returns
// (win32IntReturns table) at every call site automatically. Direct
// Win32 calls now Just Work — no cfunc wrapper needed.

import "head:process"
import "head:windows"

just run {
    // Process / thread IDs
    let pid = GetCurrentProcessId()
    let tid = GetCurrentThreadId()
    print("pid=" + pid + " tid=" + tid)

    // Tick + sleep round trip
    let t0 = GetTickCount()
    print("Sleeping 750 ms...")
    Sleep(750)
    let t1 = GetTickCount()
    let dt = toInt(t1) - toInt(t0)
    print("elapsed=" + dt + " ms (expect ~750)")

    // 64-bit tick counter
    let big0 = GetTickCount64()
    Sleep(100)
    let big1 = GetTickCount64()
    print("tick64 dt=" + (toInt(big1) - toInt(big0)) + " ms")

    // GetLastError round-trip
    SetLastError(0)
    print("err0=" + GetLastError())   // expect 0
    SetLastError(42)
    print("err1=" + GetLastError())   // expect 42

    // Logical drives bitmap
    print("drives_bitmap=" + GetLogicalDrives())
}
