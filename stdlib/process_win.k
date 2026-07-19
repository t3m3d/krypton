// stdlib/process_win.k -- shell-free Windows proc execution.
//
// Process descriptor payload (64 bytes):
//   0 stdout read, 8 stderr read, 16 stdin write, 24 proc, 32 job,
//   40 pid, 44 state, 48 last error, 52 exit code, 56 job error.

module process_win

import "k:bytes"
import "k:process_win_argv"
import "k:process_win_env"
import "head:windows"
import "head:fileio"
import "head:process"
func _processDwordMax() { emit 1073741824 * 4 - 1 }

func _processSetFlag(flags, bit) {
    let value = toInt(flags)
    if value / bit % 2 == 1 { emit value }
    emit value + bit
}

func _processNew() {
    let proc = bytesWithLength(64)
    bytesZero(proc, 0, 64)
    emit proc
}

func processIsValid(proc) { emit bytesReadUPtrLE(proc, 24) != "0" }
func processPid(proc) { emit bytesReadU32LE(proc, 40) }
func processState(proc) { emit bytesReadU32LE(proc, 44) }
func processLastError(proc) { emit bytesReadU32LE(proc, 48) }
func processExitCode(proc) { emit bytesReadU32LE(proc, 52) }
func processJobError(proc) { emit bytesReadU32LE(proc, 56) }

func _processSetError(proc, errorCode) {
    bytesWriteU32LE(proc, 48, errorCode)
}

func _processCloseHandleValue(handle) {
    if handle != "0" && handle != 0 { CloseHandle(handle) }
}

func _processClosePipeSet(a, b, c, d, e, f) {
    _processCloseHandleValue(a)
    _processCloseHandleValue(b)
    _processCloseHandleValue(c)
    _processCloseHandleValue(d)
    _processCloseHandleValue(e)
    _processCloseHandleValue(f)
}

// options:
//   inherit_environment=1 (default), no_window=1 (default), tree=1 (default)
//   creation_flags=<DWORD>
func processSpawn(executable, args, environment, cwd, options) {
    let proc = _processNew()
    if executable == "" {
        _processSetError(proc, 87)
        emit proc
    }

    // SECURITY_ATTRIBUTES: 24 bytes on Win64.
    let sa = bufNew(24)
    bufSetDwordAt(sa, 0, 24)
    bufSetQwordAt(sa, 8, 0)
    bufSetDwordAt(sa, 16, 1)

    let outReadPtr = bufNew(8)
    let outWritePtr = bufNew(8)
    if CreatePipe(outReadPtr, outWritePtr, ptrToInt(sa), 65536) == "0" {
        let errorCode = GetLastError()
        _processSetError(proc, errorCode)
        emit proc
    }
    let outRead = bufGetQword(outReadPtr)
    let outWrite = bufGetQword(outWritePtr)

    let errReadPtr = bufNew(8)
    let errWritePtr = bufNew(8)
    if CreatePipe(errReadPtr, errWritePtr, ptrToInt(sa), 65536) == "0" {
        let errorCode = GetLastError()
        _processCloseHandleValue(outRead)
        _processCloseHandleValue(outWrite)
        _processSetError(proc, errorCode)
        emit proc
    }
    let errRead = bufGetQword(errReadPtr)
    let errWrite = bufGetQword(errWritePtr)

    let inReadPtr = bufNew(8)
    let inWritePtr = bufNew(8)
    if CreatePipe(inReadPtr, inWritePtr, ptrToInt(sa), 65536) == "0" {
        let errorCode = GetLastError()
        _processClosePipeSet(outRead, outWrite, errRead, errWrite, 0, 0)
        _processSetError(proc, errorCode)
        emit proc
    }
    let inRead = bufGetQword(inReadPtr)
    let inWrite = bufGetQword(inWritePtr)

    if SetHandleInformation(outRead, 1, 0) == "0" ||
       SetHandleInformation(errRead, 1, 0) == "0" ||
       SetHandleInformation(inWrite, 1, 0) == "0" {
        let errorCode = GetLastError()
        _processClosePipeSet(outRead, outWrite, errRead, errWrite, inRead, inWrite)
        _processSetError(proc, errorCode)
        emit proc
    }

    let si = bufNew(104)
    bufSetDwordAt(si, 0, 104)
    bufSetDwordAt(si, 60, 256)
    bufSetQwordAt(si, 80, inRead)
    bufSetQwordAt(si, 88, outWrite)
    bufSetQwordAt(si, 96, errWrite)
    let pi = bufNew(24)

    let commandLine = utf16leEncode(processCommandLine(executable, args), 1)
    let appName = utf16leEncode(executable, 1)

    let inheritEnvironment = _processMapValue(options, "inherit_environment", "1")
    let environmentPtr = "0"
    let environmentBlock = bytesNew(0)
    let creationFlags = toInt(_processMapValue(options, "creation_flags", "0"))
    if environment != "" || inheritEnvironment == "0" {
        environmentBlock = _processEnvironmentBlock(environment, inheritEnvironment)
        environmentPtr = ptrToInt(bytesRaw(environmentBlock))
        creationFlags = _processSetFlag(creationFlags, 1024)
    }

    if _processMapValue(options, "no_window", "1") != "0" {
        creationFlags = _processSetFlag(creationFlags, 134217728)
    }

    let useJob = _processMapValue(options, "tree", "1") != "0"
    let job = "0"
    if useJob {
        job = CreateJobObjectW(0, 0)
        if job == "0" {
            let jobError = GetLastError()
            _processClosePipeSet(outRead, outWrite, errRead, errWrite, inRead, inWrite)
            bytesWriteU32LE(proc, 56, jobError)
            _processSetError(proc, jobError)
            emit proc
        }
        creationFlags = _processSetFlag(creationFlags, 4)
    }

    let cwdPtr = "0"
    let cwdWide = bytesNew(0)
    if cwd != "" {
        cwdWide = utf16leEncode(cwd, 1)
        cwdPtr = ptrToInt(bytesRaw(cwdWide))
    }

    let created = CreateProcessW(
        ptrToInt(bytesRaw(appName)),
        ptrToInt(bytesRaw(commandLine)),
        0,
        0,
        1,
        creationFlags,
        environmentPtr,
        cwdPtr,
        si,
        pi
    )
    let createError = 0
    if created == "0" { createError = GetLastError() }

    // Child-side copies must close in parent for correct EOF behavior.
    _processCloseHandleValue(inRead)
    _processCloseHandleValue(outWrite)
    _processCloseHandleValue(errWrite)

    if created == "0" {
        _processClosePipeSet(outRead, errRead, inWrite, job, 0, 0)
        _processSetError(proc, createError)
        emit proc
    }

    let processHandle = bufGetQwordAt(pi, 0)
    let threadHandle = bufGetQwordAt(pi, 8)
    let pid = bufGetDwordAt(pi, 16)

    if job != "0" {
        if AssignProcessToJobObject(job, processHandle) == "0" {
            let jobError = GetLastError()
            TerminateProcess(processHandle, 1)
            _processClosePipeSet(outRead, errRead, inWrite, processHandle, threadHandle, job)
            bytesWriteU32LE(proc, 56, jobError)
            _processSetError(proc, jobError)
            emit proc
        }
    }

    let resumed = ResumeThread(threadHandle)
    if resumed == _processDwordMax() {
        let resumeError = GetLastError()
        if job != "0" { TerminateJobObject(job, 1) }
        else { TerminateProcess(processHandle, 1) }
        _processClosePipeSet(outRead, errRead, inWrite, processHandle, threadHandle, job)
        _processSetError(proc, resumeError)
        emit proc
    }

    CloseHandle(threadHandle)
    bytesWriteUPtrLE(proc, 0, outRead)
    bytesWriteUPtrLE(proc, 8, errRead)
    bytesWriteUPtrLE(proc, 16, inWrite)
    bytesWriteUPtrLE(proc, 24, processHandle)
    bytesWriteUPtrLE(proc, 32, job)
    bytesWriteU32LE(proc, 40, pid)
    bytesWriteU32LE(proc, 44, 1)
    emit proc
}

func _processReadAvailable(proc, handleOffset, maxBytes) {
    let empty = bytesNew(0)
    if !processIsValid(proc) { emit empty }
    let handle = bytesReadUPtrLE(proc, handleOffset)
    if handle == "0" { emit empty }

    let availablePtr = bufNew(8)
    if PeekNamedPipe(handle, toHandle(0), 0, toHandle(0), availablePtr, toHandle(0)) == "0" {
        _processSetError(proc, GetLastError())
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
    if ReadFile(handle, bytesRaw(output), want, readPtr, 0) == "0" {
        _processSetError(proc, GetLastError())
        emit empty
    }
    bytesSetLength(output, toInt(bufGetDword(readPtr)))
    emit output
}

func processReadStdout(proc, maxBytes) {
    emit _processReadAvailable(proc, 0, maxBytes)
}

func processReadStderr(proc, maxBytes) {
    emit _processReadAvailable(proc, 8, maxBytes)
}

func processWriteStdin(proc, data) {
    if !processIsValid(proc) { emit -1 }
    let handle = bytesReadUPtrLE(proc, 16)
    if handle == "0" { emit -1 }

    let total = 0
    while total < bytesLen(data) {
        let wrotePtr = bufNew(8)
        let wanted = bytesLen(data) - total
        if WriteFile(handle, ptrAdd(bytesRaw(data), total), wanted, wrotePtr, 0) == "0" {
            _processSetError(proc, GetLastError())
            emit -1
        }
        let wrote = toInt(bufGetDword(wrotePtr))
        if wrote <= 0 { emit total }
        total += wrote
    }
    emit total
}

func processCloseStdin(proc) {
    let handle = bytesReadUPtrLE(proc, 16)
    if handle != "0" {
        CloseHandle(handle)
        bytesWriteUPtrLE(proc, 16, 0)
    }
    emit 1
}

// Returns exit code, -2 on timeout, -1 on API error.
func processWait(proc, timeoutMs) {
    if !processIsValid(proc) { emit -1 }
    let timeout = toInt(timeoutMs)
    if timeout < 0 { timeout = _processDwordMax() }
    let status = WaitForSingleObject(bytesReadUPtrLE(proc, 24), timeout)
    if status == "258" { emit -2 }
    if status != "0" {
        _processSetError(proc, GetLastError())
        emit -1
    }
    let codePtr = bufNew(8)
    if GetExitCodeProcess(bytesReadUPtrLE(proc, 24), codePtr) == "0" {
        _processSetError(proc, GetLastError())
        emit -1
    }
    let code = bufGetDword(codePtr)
    bytesWriteU32LE(proc, 44, 2)
    bytesWriteU32LE(proc, 52, code)
    emit code
}

func processAlive(proc) {
    if !processIsValid(proc) { emit 0 }
    let codePtr = bufNew(8)
    if GetExitCodeProcess(bytesReadUPtrLE(proc, 24), codePtr) == "0" {
        _processSetError(proc, GetLastError())
        emit 0
    }
    emit bufGetDword(codePtr) == "259"
}

func processKill(proc, tree) {
    if !processIsValid(proc) { emit 0 }
    let ok = "0"
    let job = bytesReadUPtrLE(proc, 32)
    if tree && job != "0" {
        ok = TerminateJobObject(job, 1)
    }
    if ok == "0" {
        ok = TerminateProcess(bytesReadUPtrLE(proc, 24), 1)
    }
    if ok == "0" {
        _processSetError(proc, GetLastError())
        emit 0
    }
    bytesWriteU32LE(proc, 44, 3)
    emit 1
}

func processClose(proc) {
    processCloseStdin(proc)
    _processCloseHandleValue(bytesReadUPtrLE(proc, 0))
    _processCloseHandleValue(bytesReadUPtrLE(proc, 8))
    _processCloseHandleValue(bytesReadUPtrLE(proc, 24))
    _processCloseHandleValue(bytesReadUPtrLE(proc, 32))
    bytesWriteUPtrLE(proc, 0, 0)
    bytesWriteUPtrLE(proc, 8, 0)
    bytesWriteUPtrLE(proc, 24, 0)
    bytesWriteUPtrLE(proc, 32, 0)
    bytesWriteU32LE(proc, 44, 4)
    emit 1
}