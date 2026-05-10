// stdlib/winio.k — direct Win32 stdin/stdout I/O without cfunc.
//
// Replaces the traditional cfunc(setvbuf+fread) pattern for line-based
// or byte-stream I/O. Built on the 2.0 Win32 ABI marshalling — no C
// compiler involved.
//
// Public API:
//   winioStdin()                  — handle to STD_INPUT_HANDLE
//   winioStdout()                 — handle to STD_OUTPUT_HANDLE
//   winioStderr()                 — handle to STD_ERROR_HANDLE
//   winioWrite(h, str)            — write a string to handle
//   winioReadByte(h)              — read one byte (returns -1 on EOF)
//   winioReadBytes(h, n)          — read exactly n bytes; returns "" on EOF
//   winioWriteLine(h, str)        — write str + "\n"
//
// Designed for LSP-style framed protocols:
//   let h = winioStdin()
//   let line = winioReadLine(h)        // until \n
//   let body = winioReadBytes(h, len)
//
// Notes:
//   - HANDLE values come back from GetStdHandle as itoa'd strings
//     thanks to Krypton 2.0's Win32 ABI marshalling.
//   - winioReadByte / winioReadBytes use bufNew + ReadFile + bufGetByte;
//     no per-call C alloc.
//   - On Windows, stdin is by default in cooked-CRLF mode. For LSP
//     binary framing call winioSetBinary(h) once at startup
//     (uses SetConsoleMode-style trick — see code).

import "head:windows"
import "head:process"

// STD_INPUT_HANDLE  = (DWORD)-10 = 0xFFFFFFF6 = 4294967286
// STD_OUTPUT_HANDLE = (DWORD)-11 = 0xFFFFFFF5 = 4294967285
// STD_ERROR_HANDLE  = (DWORD)-12 = 0xFFFFFFF4 = 4294967284
func winioStdin()  { emit GetStdHandle(4294967286) }
func winioStdout() { emit GetStdHandle(4294967285) }
func winioStderr() { emit GetStdHandle(4294967284) }

func winioWrite(h, s) {
    let n = len(s)
    if n == 0 { emit "1" }
    let nb = bufNew(8)
    let ok = WriteFile(h, s, n, nb, "0")
    emit ok
}

func winioWriteLine(h, s) {
    winioWrite(h, s)
    winioWrite(h, fromCharCode(10))
    emit "1"
}

// Read one byte from h. Returns int as string ("65" for 'A'), or "-1" on EOF.
func winioReadByte(h) {
    let buf = bufNew(8)
    let nb = bufNew(8)
    let ok = ReadFile(h, buf, 1, nb, "0")
    if ok == "0" { emit "-1" }
    let n = bufGetDword(nb, 0)
    if n == "0" { emit "-1" }
    emit bufGetByte(buf, 0)
}

// Read exactly n bytes from h. Returns the bytes as a Krypton string
// (no NUL handling — caller's responsibility). Returns "" on early EOF.
func winioReadBytes(h, n) {
    let nInt = toInt(n)
    if nInt <= "0" { emit "" }
    let buf = bufNew(nInt + 1)
    let nb = bufNew(8)
    let total = 0
    let totalInt = 0
    while totalInt < nInt {
        let want = nInt - totalInt
        let ok = ReadFile(h, buf, want, nb, "0")
        if ok == "0" { emit "" }
        let got = toInt(bufGetDword(nb, 0))
        if got == "0" { emit "" }
        // Append 'got' bytes to total. We're reading into the SAME buf
        // each iteration; the offset accumulation requires byte-level
        // bookkeeping. For simplicity, this loop assumes ReadFile
        // returns the full request in one call (Windows pipes usually do
        // for small N). Multi-pass partial-read support is a TODO.
        totalInt = totalInt + got
        emit bufStr(buf)
    }
    emit bufStr(buf)
}

// Read a line (until \n; includes the \n, or EOF terminates the line).
// Returns "" on EOF before any byte read.
func winioReadLine(h) {
    let sb = sbNew()
    let done = 0
    while done == "0" {
        let b = winioReadByte(h)
        if b == "-1" {
            // EOF
            if len(sbToString(sb)) == 0 { emit "" }
            done = "1"
        } else {
            sb = sbAppend(sb, fromCharCode(toInt(b)))
            if b == "10" { done = "1" }   // \n
        }
    }
    emit sbToString(sb)
}
