// stdlib/proc.k — bidirectional process pipes for Krypton.
//
// 2.1: pure Krypton via direct Win32 IAT. No cfunc body, no
// ckrypton_proc.dll. The handle returned by procSpawn is a comma-
// separated string "hOutRead,hInWrite,hProcess,pid" — each field
// is the decimal int form of the underlying HANDLE / DWORD.
//
//   import "k:proc"
//
//   let p = procSpawn("kls.exe", "")
//   procWrite(p, "Content-Length: 26\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1}")
//   let reply = procRead(p, 4096)
//   procClose(p)

module proc

import "head:windows"
import "head:fileio"
import "head:process"

jxt {
    c "windows.h"
    func CreatePipe(hRead, hWrite, sa, size)
    func PeekNamedPipe(handle, buf, bufSize, bytesRead, totalAvail, msgLeft)
    func SetHandleInformation(handle, mask, flags)
}


// ── Handle-string encoding helpers ─────────────────────────────

func _proc_pack(hOutRead, hInWrite, hProcess, pid) {
    emit hOutRead + "," + hInWrite + "," + hProcess + "," + pid
}

// Read field idx from a comma-separated string. Build via sb because
// kr_plus on two all-digit strings is arithmetic, not concat — so the
// naive `part + ch` loop gives wrong results for handle strings.
func _proc_field(h, idx) {
    let i = 0
    let sb = sbNew()
    let n = 0
    while i < len(h) {
        let ch = substring(h, i, i + 1)
        if ch == "," {
            if n == idx { emit sbToString(sb) }
            sb = sbNew()
            n += 1
        } else {
            sb = sbAppend(sb, ch)
        }
        i += 1
    }
    if n == idx { emit sbToString(sb) }
    emit ""
}

func _proc_hOutRead(h)  { emit _proc_field(h, 0) }
func _proc_hInWrite(h)  { emit _proc_field(h, 1) }
func _proc_hProcess(h)  { emit _proc_field(h, 2) }
func _proc_pid(h)       { emit _proc_field(h, 3) }


// ── Public API ─────────────────────────────────────────────────

// Spawn `exe` with `args`. Returns the encoded handle on success,
// "0" on failure.
func procSpawn(exe, args) {
    // SECURITY_ATTRIBUTES (24 bytes): nLength=24 @0, lpSecurityDescriptor=NULL @8, bInheritHandle=TRUE @16
    let sa = bufNew("24")
    bufSetDword(sa, "24")        // nLength = 24 (full struct size)
    bufSetQwordAt(sa, "8", "0")  // lpSecurityDescriptor = NULL
    bufSetDwordAt(sa, "16", "1") // bInheritHandle = TRUE

    // Create stdout pipe (parent reads, child writes).
    let pOutRead  = bufNew("8")
    let pOutWrite = bufNew("8")
    let okOut = CreatePipe(pOutRead, pOutWrite, sa, "1048576")
    if okOut == "0" { emit "0" }
    let hOutRead  = bufGetQword(pOutRead)
    let hOutWrite = bufGetQword(pOutWrite)
    SetHandleInformation(hOutRead, "1", "0")  // HANDLE_FLAG_INHERIT=1, clear

    // Create stdin pipe (parent writes, child reads).
    let pInRead  = bufNew("8")
    let pInWrite = bufNew("8")
    let okIn = CreatePipe(pInRead, pInWrite, sa, "1048576")
    if okIn == "0" {
        CloseHandle(hOutRead)
        CloseHandle(hOutWrite)
        emit "0"
    }
    let hInRead  = bufGetQword(pInRead)
    let hInWrite = bufGetQword(pInWrite)
    SetHandleInformation(hInWrite, "1", "0")

    // Build full command line: exe + " " + args (always single string for CreateProcessA).
    let cmd = exe
    if len(args) > 0 { cmd = exe + " " + args }

    // STARTUPINFOA (104 bytes; we zero-init via bufNew + manual writes)
    //   cb=4 @0, dwFlags=4 @60, wShowWindow=2 @64,
    //   hStdInput=8 @80, hStdOutput=8 @88, hStdError=8 @96
    let si = bufNew("104")
    bufSetDword(si, "104")              // cb
    bufSetDwordAt(si, "60", "256")      // dwFlags = STARTF_USESTDHANDLES (0x100)
    bufSetQwordAt(si, "80", hInRead)    // hStdInput
    bufSetQwordAt(si, "88", hOutWrite)  // hStdOutput
    bufSetQwordAt(si, "96", hOutWrite)  // hStdError (merge into stdout)

    // PROCESS_INFORMATION (24 bytes — out)
    let pi = bufNew("24")

    //   CREATE_NO_WINDOW = 0x08000000 = 134217728
    let okCreate = CreateProcessA(toHandle("0"), cmd, "0", "0", "1", "134217728", "0", toHandle("0"), si, pi)

    // Close parent's copies of child-side handles (EOF propagation).
    CloseHandle(hInRead)
    CloseHandle(hOutWrite)

    if okCreate == "0" {
        CloseHandle(hOutRead)
        CloseHandle(hInWrite)
        emit "0"
    }

    let hProcess = bufGetQword(pi)
    let hThread  = bufGetQwordAt(pi, "8")
    let pid      = bufGetDwordAt(pi, "16")
    CloseHandle(hThread)  // unused

    emit _proc_pack(hOutRead, hInWrite, hProcess, pid)
}

func procWrite(h, data) {
    if h == "0" { emit "0" }
    let hWrite = _proc_hInWrite(h)
    let n = len(data)
    let nb = bufNew("8")
    let ok = WriteFile(hWrite, data, n + "", nb, "0")
    if ok == "0" { emit "0" }
    let wrote = toInt(bufGetDword(nb))
    if wrote != n { emit "0" }
    emit "1"
}

func procRead(h, maxBytes) {
    if h == "0" { emit "" }
    let cap = toInt(maxBytes)
    if cap <= 0 { cap = 4096 }
    if cap > 1048576 { cap = 1048576 }
    let hRead = _proc_hOutRead(h)
    let buf = bufNew(cap + 1)
    let nb  = bufNew("8")
    let ok = ReadFile(hRead, buf, cap + "", nb, "0")
    if ok == "0" { emit "" }
    let got = toInt(bufGetDword(nb))
    if got == 0 { emit "" }
    emit bufStr(buf)
}

func procReadAvail(h, maxBytes) {
    if h == "0" { emit "" }
    let cap = toInt(maxBytes)
    if cap <= 0 { cap = 4096 }
    if cap > 1048576 { cap = 1048576 }
    let hRead = _proc_hOutRead(h)
    let availBuf = bufNew("8")
    let ok = PeekNamedPipe(hRead, toHandle("0"), "0", toHandle("0"), availBuf, toHandle("0"))
    if ok == "0" { emit "" }
    let avail = toInt(bufGetDword(availBuf))
    if avail == 0 { emit "" }
    let want = cap
    if avail < want { want = avail }
    let buf = bufNew(want + 1)
    let nb  = bufNew("8")
    let okR = ReadFile(hRead, buf, want + "", nb, "0")
    if okR == "0" { emit "" }
    let got = toInt(bufGetDword(nb))
    if got == 0 { emit "" }
    emit bufStr(buf)
}

func procAlive(h) {
    if h == "0" { emit "0" }
    let hProcess = _proc_hProcess(h)
    let codeBuf = bufNew("8")
    let ok = GetExitCodeProcess(hProcess, codeBuf)
    if ok == "0" { emit "0" }
    let code = toInt(bufGetDword(codeBuf))
    // STILL_ACTIVE = 259 = 0x103
    if code == 259 { emit "1" }
    emit "0"
}

func procClose(h) {
    if h == "0" { emit "1" }
    let hOutRead  = _proc_hOutRead(h)
    let hInWrite  = _proc_hInWrite(h)
    let hProcess  = _proc_hProcess(h)
    // Shut stdin first so child sees EOF.
    if hInWrite != "0" { CloseHandle(hInWrite) }
    WaitForSingleObject(hProcess, "500")
    let codeBuf = bufNew("8")
    if GetExitCodeProcess(hProcess, codeBuf) != "0" {
        let code = toInt(bufGetDword(codeBuf))
        if code == 259 { TerminateProcess(hProcess, "1") }
    }
    if hOutRead != "0" { CloseHandle(hOutRead) }
    CloseHandle(hProcess)
    emit "1"
}

// procSleep: direct Sleep (kernel32) via Win32 marshalling.
func procSleep(ms) {
    Sleep(ms)
    emit "1"
}
