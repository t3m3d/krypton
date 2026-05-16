import "head:windows"

func cpubrand() {
    let regPath = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"
    let name    = trim(regHklmStr(regPath, "ProcessorNameString"))
    if name == "" { emit "Unknown CPU" }
    emit name
}

func cpucores() {
    // 2.0: skip LoadLibraryA/GetProcAddress dance (HMODULE 1.x raw-pointer
    // convention is incompatible with marshalled FreeLibrary). Just report
    // logical=physical from GetNativeSystemInfo.
    let si      = structNew("SYSTEM_INFO")
    GetNativeSystemInfo(si)
    let logical = structGet(si, "SYSTEM_INFO", "dwNumberOfProcessors")
    emit logical + "," + logical
}
