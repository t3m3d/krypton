// test_struct_api.k - Test extern struct system

import "headers/windows.krh"

just run {
    // Test structNew + GlobalMemoryStatusEx
    let ms = structNew("MEMORYSTATUSEX")
    structSet(ms, "MEMORYSTATUSEX", "dwLength", sizeOf("MEMORYSTATUSEX"))
    GlobalMemoryStatusEx(ms)

    let totalMB = div64(structGet(ms, "MEMORYSTATUSEX", "ullTotalPhys"), "1048576")
    let availMB = div64(structGet(ms, "MEMORYSTATUSEX", "ullAvailPhys"), "1048576")

    kp("Total RAM: " + totalMB + " MB")
    kp("Avail RAM: " + availMB + " MB")

    if toInt(totalMB) > 0 {
        kp("PASS struct GlobalMemoryStatusEx works")
    } else {
        kp("FAIL got zero")
    }

    // Test console size
    let h = GetStdHandle("-10")
    let csbi = structNew("CONSOLE_SCREEN_BUFFER_INFO")
    GetConsoleScreenBufferInfo(h, csbi)
    let cols = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowRight")) - toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowLeft")) + 1 + ""
    kp("Console cols: " + cols)

    if toInt(cols) > 0 {
        kp("PASS struct GetConsoleScreenBufferInfo works")
    } else {
        kp("FAIL console size")
    }

    kp("ALL STRUCT API TESTS PASSED")
}
