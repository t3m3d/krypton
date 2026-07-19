// stdlib/conpty_win.k -- persistent Windows pseudo-console sessions.
//
// ConPTY is available on Windows 10 1809+. Reads are nonblocking byte-buffer
// polls suitable for a UI timer or a future background-task dispatcher.
//
// Session payload (64 bytes):
//   0 output read, 8 input write, 16 process, 24 HPCON, 32 job,
//   40 pid, 44 state, 48 last error/HRESULT, 52 exit code,
//   56 columns, 60 rows.

module conpty_win

import "k:bytes"
import "k:process_win_argv"
import "k:process_win_env"
import "head:windows"
import "head:fileio"
import "head:process"

func _conptyNew() {
    let session = bytesWithLength(64)
    bytesZero(session, 0, 64)
    emit session
}

func _conptySetError(session, code) {
    bytesWriteU32LE(session, 48, code)
}

func _conptyCloseHandle(handle) {
    if handle != "0" && handle != 0 { CloseHandle(handle) }
}

func _conptyCloseHandles(a, b, c, d, e) {
    _conptyCloseHandle(a)
    _conptyCloseHandle(b)
    _conptyCloseHandle(c)
    _conptyCloseHandle(d)
    _conptyCloseHandle(e)
}

func _conptyCoord(columns, rows) {
    let x = _conptyClampAxis(columns)
    let y = _conptyClampAxis(rows)
    emit x + y * 65536
}

func _conptyClampAxis(value) {
    let x = toInt(value)
    if x < 1 { x = 1 }
    if x > 32767 { x = 32767 }
    emit x
}

func _conptyDwordMax() { emit 1073741824 * 4 - 1 }

func _conptySetFlag(flags, bit) {
    let value = toInt(flags)
    if value / bit % 2 == 1 { emit value }
    emit value + bit
}

func conptyTerminalEnvironment(environment) {
    let out = environment
    out = processEnvironmentSet(out, "TERM", "xterm-256color")
    out = processEnvironmentSet(out, "COLORTERM", "truecolor")
    out = processEnvironmentRemove(out, "NO_COLOR")
    emit out
}

func conptyIsValid(session) { emit bytesReadUPtrLE(session, 16) != "0" }
func conptyPid(session) { emit bytesReadU32LE(session, 40) }
func conptyState(session) { emit bytesReadU32LE(session, 44) }
func conptyLastError(session) { emit bytesReadU32LE(session, 48) }
func conptyExitCode(session) { emit bytesReadU32LE(session, 52) }
func conptyColumns(session) { emit bytesReadU32LE(session, 56) }
func conptyRows(session) { emit bytesReadU32LE(session, 60) }

// options accepts tree=1 (default), no_window=0 (default), and
// creation_flags=<DWORD>. Empty cwd defaults to USERPROFILE.
func conptySpawn(executable, args, environment, cwd, columns, rows, options) {
    let session = _conptyNew()
    if executable == "" {
        _conptySetError(session, 87)
        emit session
    }

    let pseudoInReadPtr = bufNew(8)
    let parentInWritePtr = bufNew(8)
    if CreatePipe(pseudoInReadPtr, parentInWritePtr, 0, 65536) == "0" {
        _conptySetError(session, GetLastError())
        emit session
    }
    let pseudoInRead = bufGetQword(pseudoInReadPtr)
    let parentInWrite = bufGetQword(parentInWritePtr)

    let parentOutReadPtr = bufNew(8)
    let pseudoOutWritePtr = bufNew(8)
    if CreatePipe(parentOutReadPtr, pseudoOutWritePtr, 0, 65536) == "0" {
        let errorCode = GetLastError()
        _conptyCloseHandle(pseudoInRead)
        _conptyCloseHandle(parentInWrite)
        _conptySetError(session, errorCode)
        emit session
    }
    let parentOutRead = bufGetQword(parentOutReadPtr)
    let pseudoOutWrite = bufGetQword(pseudoOutWritePtr)

    let pseudoConsolePtr = bufNew(8)
    let createPseudo = CreatePseudoConsole(
        _conptyCoord(columns, rows),
        pseudoInRead,
        pseudoOutWrite,
        0,
        pseudoConsolePtr
    )
    let pseudoConsole = "0"
    if createPseudo == "0" { pseudoConsole = bufGetQword(pseudoConsolePtr) }

    // ConPTY owns duplicated pipe ends after successful creation.
    _conptyCloseHandle(pseudoInRead)
    _conptyCloseHandle(pseudoOutWrite)

    if createPseudo != "0" {
        _conptyCloseHandle(parentInWrite)
        _conptyCloseHandle(parentOutRead)
        _conptySetError(session, createPseudo)
        emit session
    }

    let attributeBytesPtr = bufNew(8)
    InitializeProcThreadAttributeList(0, 1, 0, attributeBytesPtr)
    let attributeBytes = toInt(bufGetQword(attributeBytesPtr))
    if attributeBytes <= 0 {
        let errorCode = GetLastError()
        ClosePseudoConsole(pseudoConsole)
        _conptyCloseHandle(parentInWrite)
        _conptyCloseHandle(parentOutRead)
        _conptySetError(session, errorCode)
        emit session
    }

    let attributes = bufNew(attributeBytes)
    if InitializeProcThreadAttributeList(ptrToInt(attributes), 1, 0, attributeBytesPtr) == "0" {
        let errorCode = GetLastError()
        ClosePseudoConsole(pseudoConsole)
        _conptyCloseHandle(parentInWrite)
        _conptyCloseHandle(parentOutRead)
        _conptySetError(session, errorCode)
        emit session
    }

    // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016 = 131094.
    if UpdateProcThreadAttribute(
        ptrToInt(attributes),
        0,
        131094,
        toHandle(pseudoConsole),
        8,
        0,
        0
    ) == "0" {
        let errorCode = GetLastError()
        DeleteProcThreadAttributeList(ptrToInt(attributes))
        ClosePseudoConsole(pseudoConsole)
        _conptyCloseHandle(parentInWrite)
        _conptyCloseHandle(parentOutRead)
        _conptySetError(session, errorCode)
        emit session
    }

    let startup = bufNew(112)
    bufSetDwordAt(startup, 0, 112)
    bufSetQwordAt(startup, 104, ptrToInt(attributes))
    let procInfo = bufNew(24)

    let commandLine = utf16leEncode(processCommandLine(executable, args), 1)
    let appName = utf16leEncode(executable, 1)

    let terminalEnvironment = conptyTerminalEnvironment(environment)
    let inheritEnvironment = _processMapValue(options, "inherit_environment", "1")
    let environmentBlock = _processEnvironmentBlock(terminalEnvironment, inheritEnvironment)

    let actualCwd = cwd
    if actualCwd == "" {
        actualCwd = _processMapValue(_processParentEnvironment(), "USERPROFILE", "")
    }
    let cwdPtr = "0"
    let cwdWide = bytesNew(0)
    if actualCwd != "" {
        cwdWide = utf16leEncode(actualCwd, 1)
        cwdPtr = ptrToInt(bytesRaw(cwdWide))
    }

    let creationFlags = toInt(_processMapValue(options, "creation_flags", "0"))
    creationFlags = _conptySetFlag(creationFlags, 524288)
    creationFlags = _conptySetFlag(creationFlags, 1024)
    if _processMapValue(options, "no_window", "0") != "0" {
        creationFlags = _conptySetFlag(creationFlags, 134217728)
    }

    let useJob = _processMapValue(options, "tree", "1") != "0"
    let job = "0"
    if useJob {
        creationFlags = _conptySetFlag(creationFlags, 4)
        job = CreateJobObjectW(0, 0)
        if job == "0" {
            let jobError = GetLastError()
            DeleteProcThreadAttributeList(ptrToInt(attributes))
            ClosePseudoConsole(pseudoConsole)
            _conptyCloseHandle(parentInWrite)
            _conptyCloseHandle(parentOutRead)
            _conptySetError(session, jobError)
            emit session
        }
    }

    let created = CreateProcessW(
        ptrToInt(bytesRaw(appName)),
        ptrToInt(bytesRaw(commandLine)),
        0,
        0,
        0,
        creationFlags,
        ptrToInt(bytesRaw(environmentBlock)),
        cwdPtr,
        startup,
        procInfo
    )
    let createError = 0
    if created == "0" { createError = GetLastError() }
    DeleteProcThreadAttributeList(ptrToInt(attributes))

    if created == "0" {
        if job != "0" { CloseHandle(job) }
        ClosePseudoConsole(pseudoConsole)
        _conptyCloseHandle(parentInWrite)
        _conptyCloseHandle(parentOutRead)
        _conptySetError(session, createError)
        emit session
    }

    let procHandle = bufGetQwordAt(procInfo, 0)
    let threadHandle = bufGetQwordAt(procInfo, 8)
    let pid = bufGetDwordAt(procInfo, 16)

    if job != "0" {
        if AssignProcessToJobObject(job, procHandle) == "0" {
            let jobError = GetLastError()
            TerminateProcess(procHandle, 1)
            _conptyCloseHandles(parentInWrite, parentOutRead, procHandle, threadHandle, job)
            ClosePseudoConsole(pseudoConsole)
            _conptySetError(session, jobError)
            emit session
        }
    }

    if useJob {
        if ResumeThread(threadHandle) == _conptyDwordMax() {
            let resumeError = GetLastError()
            if job != "0" { TerminateJobObject(job, 1) }
            else { TerminateProcess(procHandle, 1) }
            _conptyCloseHandles(parentInWrite, parentOutRead, procHandle, threadHandle, job)
            ClosePseudoConsole(pseudoConsole)
            _conptySetError(session, resumeError)
            emit session
        }
    }

    CloseHandle(threadHandle)
    bytesWriteUPtrLE(session, 0, parentOutRead)
    bytesWriteUPtrLE(session, 8, parentInWrite)
    bytesWriteUPtrLE(session, 16, procHandle)
    bytesWriteUPtrLE(session, 24, pseudoConsole)
    bytesWriteUPtrLE(session, 32, job)
    bytesWriteU32LE(session, 40, pid)
    bytesWriteU32LE(session, 44, 1)
    bytesWriteU32LE(session, 56, _conptyClampAxis(columns))
    bytesWriteU32LE(session, 60, _conptyClampAxis(rows))
    emit session
}

// Nonblocking read. Empty buffer means no output currently available.
func conptyRead(session, maxBytes) {
    let empty = bytesNew(0)
    if !conptyIsValid(session) { emit empty }
    let outputHandle = bytesReadUPtrLE(session, 0)
    if outputHandle == "0" { emit empty }

    let availablePtr = bufNew(8)
    if PeekNamedPipe(outputHandle, toHandle(0), 0, toHandle(0), availablePtr, toHandle(0)) == "0" {
        _conptySetError(session, GetLastError())
        emit empty
    }
    let available = toInt(bufGetDword(availablePtr))
    if available <= 0 { emit empty }

    let want = toInt(maxBytes)
    if want <= 0 { want = 65536 }
    if want > 16777216 { want = 16777216 }
    if available < want { want = available }

    let output = bytesWithLength(want)
    let readPtr = bufNew(8)
    if ReadFile(outputHandle, bytesRaw(output), want, readPtr, 0) == "0" {
        _conptySetError(session, GetLastError())
        emit empty
    }
    bytesSetLength(output, toInt(bufGetDword(readPtr)))
    emit output
}

func conptyWrite(session, data) {
    if !conptyIsValid(session) { emit -1 }
    let inputHandle = bytesReadUPtrLE(session, 8)
    if inputHandle == "0" { emit -1 }

    let total = 0
    while total < bytesLen(data) {
        let wrotePtr = bufNew(8)
        let wanted = bytesLen(data) - total
        if WriteFile(inputHandle, ptrAdd(bytesRaw(data), total), wanted, wrotePtr, 0) == "0" {
            _conptySetError(session, GetLastError())
            emit -1
        }
        let wrote = toInt(bufGetDword(wrotePtr))
        if wrote <= 0 { emit total }
        total += wrote
    }
    emit total
}

func conptyResize(session, columns, rows) {
    if !conptyIsValid(session) { emit 0 }
    let result = ResizePseudoConsole(bytesReadUPtrLE(session, 24), _conptyCoord(columns, rows))
    if result != "0" {
        _conptySetError(session, result)
        emit 0
    }
    bytesWriteU32LE(session, 56, _conptyClampAxis(columns))
    bytesWriteU32LE(session, 60, _conptyClampAxis(rows))
    emit 1
}

func conptyCloseInput(session) {
    let inputHandle = bytesReadUPtrLE(session, 8)
    if inputHandle != "0" {
        CloseHandle(inputHandle)
        bytesWriteUPtrLE(session, 8, 0)
    }
    emit 1
}

// Returns exit code, -2 on timeout, -1 on API error.
func conptyWait(session, timeoutMs) {
    if !conptyIsValid(session) { emit -1 }
    let timeout = toInt(timeoutMs)
    if timeout < 0 { timeout = _conptyDwordMax() }
    let status = WaitForSingleObject(bytesReadUPtrLE(session, 16), timeout)
    if status == "258" { emit -2 }
    if status != "0" {
        _conptySetError(session, GetLastError())
        emit -1
    }
    let codePtr = bufNew(8)
    if GetExitCodeProcess(bytesReadUPtrLE(session, 16), codePtr) == "0" {
        _conptySetError(session, GetLastError())
        emit -1
    }
    let code = bufGetDword(codePtr)
    bytesWriteU32LE(session, 44, 2)
    bytesWriteU32LE(session, 52, code)
    emit code
}

func conptyAlive(session) {
    if !conptyIsValid(session) { emit 0 }
    let codePtr = bufNew(8)
    if GetExitCodeProcess(bytesReadUPtrLE(session, 16), codePtr) == "0" {
        _conptySetError(session, GetLastError())
        emit 0
    }
    emit bufGetDword(codePtr) == "259"
}

func conptyKill(session, tree) {
    if !conptyIsValid(session) { emit 0 }
    let ok = "0"
    let job = bytesReadUPtrLE(session, 32)
    if tree && job != "0" { ok = TerminateJobObject(job, 1) }
    if ok == "0" { ok = TerminateProcess(bytesReadUPtrLE(session, 16), 1) }
    if ok == "0" {
        _conptySetError(session, GetLastError())
        emit 0
    }
    bytesWriteU32LE(session, 44, 3)
    emit 1
}

func conptyClose(session) {
    conptyCloseInput(session)
    _conptyCloseHandle(bytesReadUPtrLE(session, 0))
    if bytesReadUPtrLE(session, 24) != "0" {
        ClosePseudoConsole(bytesReadUPtrLE(session, 24))
    }
    _conptyCloseHandle(bytesReadUPtrLE(session, 16))
    _conptyCloseHandle(bytesReadUPtrLE(session, 32))
    bytesWriteUPtrLE(session, 0, 0)
    bytesWriteUPtrLE(session, 16, 0)
    bytesWriteUPtrLE(session, 24, 0)
    bytesWriteUPtrLE(session, 32, 0)
    bytesWriteU32LE(session, 44, 4)
    emit 1
}