import "head:windows"

func raminfo() {
    let ms = structNew("MEMORYSTATUSEX")
    structSet(ms, "MEMORYSTATUSEX", "dwLength", sizeOf("MEMORYSTATUSEX"))
    GlobalMemoryStatusEx(ms)
    let totalMB = div64(structGet(ms, "MEMORYSTATUSEX", "ullTotalPhys"), "1048576")
    let availMB = div64(structGet(ms, "MEMORYSTATUSEX", "ullAvailPhys"), "1048576")
    emit totalMB + "," + availMB
}
