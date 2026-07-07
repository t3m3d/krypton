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
//   winioGet()                    — read one key, no echo when console mode allows
//   winioGetEcho()                — read one key, echo when console mode allows
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

// STD_INPUT_HANDLE  = -10
// STD_OUTPUT_HANDLE = -11
// STD_ERROR_HANDLE  = -12
func winioStdin()  { emit GetStdHandle("-10") }
func winioStdout() { emit GetStdHandle("-11") }
func winioStderr() { emit GetStdHandle("-12") }


func _winioClearBit(mode, bit) {
    if mode / bit % 2 == 1 { emit mode - bit }
    emit mode
}

func _winioSetBit(mode, bit) {
    if mode / bit % 2 == 0 { emit mode + bit }
    emit mode
}

func _winioReadKey(echo) {
    let h = winioStdin()
    let mode = bufNew(8)
    let changed = 0
    let oldMode = 0
    if GetConsoleMode(h, mode) != "0" {
        oldMode = toInt(bufGetDword(mode))
        let newMode = _winioClearBit(oldMode, 2)
        if echo == "0" { newMode = _winioClearBit(newMode, 4) }
        else { newMode = _winioSetBit(newMode, 4) }
        SetConsoleMode(h, newMode)
        changed = 1
    }
    let b = winioReadByte(h)
    if changed == 1 { SetConsoleMode(h, oldMode) }
    if b == "-1" { emit "" }
    emit fromCharCode(toInt(b))
}

func winioGet() { emit _winioReadKey("0") }
func winioGetEcho() { emit _winioReadKey("1") }

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
    let n = bufGetDword(nb)
    if n == "0" { emit "-1" }
    emit bufGetByte(buf, 0)
}

// Read exactly n bytes from h. Returns the bytes as a Krypton string
// (no NUL handling — JSON/text payloads only). Returns "" on early EOF.
//
// Multi-pass safe: ReadFile is called repeatedly into a small chunk
// buffer until n bytes have been collected. Each chunk's bytes are
// copied into the result buffer at the correct offset via bufSetByte.
// This avoids needing pointer arithmetic at the Krypton call site.
func winioReadBytes(h, n) {
    let nInt = toInt(n)
    if nInt <= 0 { emit "" }
    let result    = bufNew(nInt + 1)
    let nb        = bufNew(8)
    let chunkSize = 4096
    let chunk     = bufNew(chunkSize)
    let totalInt  = 0
    while totalInt < nInt {
        let want = nInt - totalInt
        if want > chunkSize { want = chunkSize }
        let ok = ReadFile(h, chunk, want, nb, "0")
        if ok == "0" { emit "" }
        let got = toInt(bufGetDword(nb))
        if got == 0 { emit "" }   // EOF before n bytes collected
        let i = 0
        while i < got {
            bufSetByte(result, totalInt + i, bufGetByte(chunk, i))
            i = i + 1
        }
        totalInt = totalInt + got
    }
    emit bufStr(result)
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
