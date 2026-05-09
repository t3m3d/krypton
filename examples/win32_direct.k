// 2.0-alpha-3: direct Win32 calls without cfunc wrappers.
//
// Krypton stores all values as char* pointers. Win32 functions like
// Sleep(DWORD ms) expect an int in RCX/RDX/R8/R9 — a string pointer
// gets misread as a huge integer. Previously every int-arg Win32 call
// needed a cfunc wrapper that atoi'd the string (e.g. krProcSleep in
// stdlib/proc.k).
//
// x64.k now atoi's int args at the call site for known Win32 functions
// (see win32IntArgs table). `Sleep(500)` works directly — no wrapper.

import "head:process"

just run {
    print("Sleeping 750 ms via direct Sleep(750)...")
    Sleep(750)
    print("Awake.")

    print("Sleeping another 250 ms...")
    Sleep(250)
    print("Done.")
}
