// stdlib/proc_ex.k -- process introspection wrappers around psapi.dll.
//
// Wired through the IAT in compiler/windows_x86/x64.k 2026-06-13.
//
// Usage:
//   import "k:proc_ex"
//   let pids = listProcesses()            -- newline-joined PID list
//   let name = processBaseName(pid)       -- "notepad.exe"
//   let path = processImagePath(pid)      -- "C:\Windows\notepad.exe"
//   let wsKb = processWorkingSetKb(pid)
//
// On the macOS side these calls land on libproc (proc_listpids /
// proc_pidpath / proc_pid_rusage) via Objective-K -- the function names
// here are platform-agnostic on purpose.

module proc_ex

import "head:psapi"
import "head:process"

let PROCESS_QUERY_INFO_VM = "4112"  // PROCESS_QUERY_LIMITED_INFORMATION (0x1000) | PROCESS_VM_READ (0x10)

// Returns a newline-joined string of all process IDs currently running.
// 1024-entry cap -- enough for any reasonable system; extend if needed.
func listProcesses() {
    let cap = 1024
    let buf = bufNew(toStr(cap * 4))
    let needed = bufNew("4")
    let ok = EnumProcesses(buf, toStr(cap * 4), needed)
    if ok == "0" { emit "" }
    let n = toInt(bufGetDwordAt(needed, "0")) / 4
    let out = sbNew()
    let i = 0
    while i < n {
        if i > 0 { out = sbAppend(out, "\n") }
        out = sbAppend(out, bufGetDwordAt(buf, toStr(i * 4)))
        i += 1
    }
    emit sbToString(out)
}

// Short executable name for a PID, e.g. "explorer.exe".
// Returns "" if the process can't be opened (access denied / dead).
func processBaseName(pid) {
    let h = OpenProcess(PROCESS_QUERY_INFO_VM, "0", pid)
    if ptrToInt(h) == "0" { emit "" }
    let hmod = bufNew("8")
    let needed = bufNew("4")
    let ok = EnumProcessModules(h, hmod, "8", needed)
    if ok == "0" {
        CloseHandle(h)
        emit ""
    }
    let nameBuf = bufNew("260")
    let firstMod = bufGetQwordAt(hmod, "0")
    GetModuleBaseNameA(h, firstMod, nameBuf, "260")
    CloseHandle(h)
    emit _procBufToStr(nameBuf, 260)
}

// Fully-qualified executable path for a PID.
func processImagePath(pid) {
    let h = OpenProcess(PROCESS_QUERY_INFO_VM, "0", pid)
    if ptrToInt(h) == "0" { emit "" }
    let hmod = bufNew("8")
    let needed = bufNew("4")
    let ok = EnumProcessModules(h, hmod, "8", needed)
    if ok == "0" {
        CloseHandle(h)
        emit ""
    }
    let pathBuf = bufNew("520")
    let firstMod = bufGetQwordAt(hmod, "0")
    GetModuleFileNameExA(h, firstMod, pathBuf, "520")
    CloseHandle(h)
    emit _procBufToStr(pathBuf, 520)
}

// Working set in kilobytes (RSS, roughly).  Returns "0" on failure.
// PROCESS_MEMORY_COUNTERS layout (40 bytes on x64):
//   +0  cb (DWORD)                +4  PageFaultCount (DWORD)
//   +8  PeakWorkingSetSize        +16 WorkingSetSize  (SIZE_T)
//   +24 QuotaPeakPagedPoolUsage   +32 QuotaPagedPoolUsage
func processWorkingSetKb(pid) {
    let h = OpenProcess(PROCESS_QUERY_INFO_VM, "0", pid)
    if ptrToInt(h) == "0" { emit "0" }
    let pmc = bufNew("40")
    bufSetDwordAt(pmc, "0", "40")
    let ok = GetProcessMemoryInfo(h, pmc, "40")
    CloseHandle(h)
    if ok == "0" { emit "0" }
    let ws = toInt(bufGetQwordAt(pmc, "16"))
    emit toStr(ws / 1024)
}

func _procBufToStr(buf, cap) {
    let out = sbNew()
    let i = 0
    while i < cap {
        let b = bufGetByte(buf, i)
        if b == "0" { emit sbToString(out) }
        out = sbAppend(out, chr(b))
        i += 1
    }
    emit sbToString(out)
}
