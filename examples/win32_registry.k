// 2.0 demo: direct Win32 registry access from Krypton.
//
// Reads a known HKLM value to demonstrate that all the registry
// marshalling works end-to-end. No cfunc wrapper needed — kryofetch
// previously had to wrap every Reg* call in a cfunc body for argument
// marshalling. With 2.0's Win32 ABI table, direct calls Just Work.

import "head:windows"

just run {
    let HKEY_LOCAL_MACHINE = 2147483650   // 0x80000002 unsigned
    let KEY_READ           = 131097       // 0x20019

    // Open the Windows NT/CurrentVersion key
    let phResult = bufNew(8)
    let r = RegOpenKeyExA(
        HKEY_LOCAL_MACHINE,
        "Software\\Microsoft\\Windows NT\\CurrentVersion",
        0,
        KEY_READ,
        phResult
    )

    if r != "0" {
        print("RegOpenKeyExA failed: " + r)
        emit 1
    }

    let hKey = bufGetQword(phResult, 0)
    print("Opened HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion (hKey=" + hKey + ")")

    RegCloseKey(hKey)
    print("Closed.")
    emit 0
}
