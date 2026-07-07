// stdlib/fs.k — filesystem helpers for Krypton.
//
// 2.1: pure Krypton via direct Win32 IAT. No cfunc body, no
// ckrypton_fs.dll.  Win32 ABI marshalling (atoi'd int args, itoa'd int
// returns) at the call sites makes this work through both the native
// PE pipeline (KR32_FUNCS in x64.k) and the C+gcc pipeline
// (compileWin32IntArgs in compile.k).
//
// Wire format for fsListDir:
//
//   "<type>\t<name>\n<type>\t<name>\n..."
//
// type is "D" for directory, "F" for file. Skips "." and "..".
// Entries are unsorted; caller can sort via builtin sort if desired.

module fs

import "head:windows"
import "head:fileio"


// ── Native Win32 implementations ──────────────────────────────────

// FILE_ATTRIBUTE_DIRECTORY = 0x10 = 16
// INVALID_FILE_ATTRIBUTES  = 0xFFFFFFFF = 4294967295
func fsListDir(path) {
    if len(path) == 0 { emit "" }
    let TAB = fromCharCode("9")
    let LF  = fromCharCode("10")
    let last = substring(path, len(path) - 1, len(path))
    let pattern = path
    if last != "\\" { if last != "/" { pattern = path + "\\" } }
    pattern = pattern + "*"

    let fd = structNew("WIN32_FIND_DATAA")
    let h  = FindFirstFileA(pattern, fd)
    if h == "0" { emit "" }
    if h == "-1" { emit "" }
    if h == "18446744073709551615" { emit "" }

    let sb = sbNew()
    let more = "1"
    while more == "1" {
        let attr = structGet(fd, "WIN32_FIND_DATAA", "dwFileAttributes")
        let name = structGet(fd, "WIN32_FIND_DATAA", "cFileName")
        let skip = "0"
        if name == "."  { skip = "1" }
        if name == ".." { skip = "1" }
        if skip == "0" {
            let typ = "F"
            if bitAnd(attr, "16") != "0" { typ = "D" }
            sb = sbAppend(sb, typ + TAB + name + LF)
        }
        more = FindNextFileA(h, fd)
    }
    FindClose(h)
    emit sbToString(sb)
}

func fsIsDir(path) {
    if len(path) == 0 { emit "0" }
    let a = GetFileAttributesA(path)
    if a == "4294967295" { emit "0" }
    if a == "-1" { emit "0" }
    if bitAnd(a, "16") != "0" { emit "1" }
    emit "0"
}

func fsFileExists(path) {
    if len(path) == 0 { emit "0" }
    let a = GetFileAttributesA(path)
    if a == "4294967295" { emit "0" }
    if a == "-1" { emit "0" }
    emit "1"
}

func fsMkdir(path) {
    if len(path) == 0 { emit "0" }
    emit CreateDirectoryA(path, "0")
}

// Delete a file. Returns "1" on success, "0" on failure.
func fsDelete(path) {
    if len(path) == 0 { emit "0" }
    emit DeleteFileA(path)
}

// Remove an empty directory. Returns "1" on success, "0" on failure.
func fsRmdir(path) {
    if len(path) == 0 { emit "0" }
    emit RemoveDirectoryA(path)
}

// Move/rename file or directory. Returns "1" on success, "0" on failure.
func fsRename(from, to) {
    if len(from) == 0 { emit "0" }
    if len(to)   == 0 { emit "0" }
    emit MoveFileA(from, to)
}

// Copy file. If overwrite is "1", existing dest is replaced. Returns "1" on success.
func fsCopy(from, to, overwrite) {
    if len(from) == 0 { emit "0" }
    if len(to)   == 0 { emit "0" }
    let fail = "1"
    if overwrite == "1" { fail = "0" }
    emit CopyFileA(from, to, fail)
}

// Get current working directory. Returns absolute path string (no trailing slash).
func fsCwd() {
    let buf = bufNew(1024)
    let n = GetCurrentDirectoryA("1024", buf)
    if n == "0" { emit "" }
    emit bufStr(buf)
}

// Change current working directory. Returns "1" on success, "0" on failure.
func fsChdir(path) {
    if len(path) == 0 { emit "0" }
    emit SetCurrentDirectoryA(path)
}

// Get system temp directory path (with trailing backslash, per Win32 convention).
func fsTempDir() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    if n == "0" { emit "" }
    emit bufStr(buf)
}

// Get user home directory. Reads %USERPROFILE% env var.
func fsHomeDir() {
    let buf = bufNew(1024)
    let n = GetEnvironmentVariableA("USERPROFILE", buf, "1024")
    if n == "0" { emit "" }
    emit bufStr(buf)
}

// CreateFileA with GENERIC_READ + OPEN_EXISTING for read-only access.
//   GENERIC_READ        = 0x80000000 = 2147483648
//   FILE_SHARE_READ     = 0x00000001
//   OPEN_EXISTING       = 3
//   FILE_ATTRIBUTE_NORMAL = 128
//   INVALID_HANDLE_VALUE = (HANDLE)-1 = 18446744073709551615 unsigned
func _fs_openRead(path) {
    emit CreateFileA(path, "2147483648", "1", "0", "3", "128", "0")
}

func _fs_isInvalid(h) {
    if h == "0" { emit "1" }
    if h == "18446744073709551615" { emit "1" }
    if h == "-1" { emit "1" }
    emit "0"
}

// Sniff the first 1 KB for NUL bytes — if any present, treat
// the file as binary. Cheap heuristic that handles UTF-8 text
// (no embedded NULs) vs PE/object/image files (lots of NULs).
func fsLooksBinary(path) {
    let h = _fs_openRead(path)
    if _fs_isInvalid(h) == "1" { emit "0" }
    let buf = bufNew(1024)
    let nb  = bufNew(8)
    let ok  = ReadFile(h, buf, "1024", nb, "0")
    CloseHandle(h)
    if ok == "0" { emit "0" }
    let n = toInt(bufGetDword(nb))
    let i = 0
    while i < n {
        if bufGetByte(buf, i) == "0" { emit "1" }
        i += 1
    }
    emit "0"
}

// Hex-dump up to maxBytes of `path` as a multi-line string, classic format:
//   00000000  4d 5a 90 00 03 00 00 00 04 00 00 00 ff ff 00 00  MZ..............
// 16 bytes per row, ASCII gutter.
func fsHexDump(path, maxBytes) {
    let cap = toInt(maxBytes)
    if cap <= 0 { cap = 65536 }
    if cap > 4194304 { cap = 4194304 }

    let h = _fs_openRead(path)
    if _fs_isInvalid(h) == "1" { emit "" }
    let buf = bufNew(cap)
    let nb  = bufNew(8)
    let ok  = ReadFile(h, buf, cap + "", nb, "0")
    CloseHandle(h)
    if ok == "0" { emit "" }
    let got = toInt(bufGetDword(nb))

    let SP = " "
    let SP2 = "  "
    let CR = fromCharCode("13")
    let LF = fromCharCode("10")
    let CRLF = CR + LF
    let DOT = "."

    let HEX = "0123456789abcdef"
    let sb = sbNew()
    let i = 0
    while i < got {
        let rowLen = got - i
        if rowLen > 16 { rowLen = 16 }
        // 8-digit hex offset, manual nibble extraction.  (kr_plus on
        // two all-digit strings does arithmetic, not concat — so the
        // simpler `pad + "0"` loop returns "0" instead of "00000000".)
        let off = i
        let s = 28
        while s >= 0 {
            let div = 1
            let dd = 0
            while dd < s { div = div * 2  dd += 1 }
            let nibV = (off / div) - ((off / div) / 16) * 16
            sb = sbAppend(sb, substring(HEX, nibV, nibV + 1))
            s -= 4
        }
        sb = sbAppend(sb, SP2)
        // 16 bytes hex (manual 2-char format via HEX nibbles)
        let b = 0
        while b < 16 {
            if b == 8 { sb = sbAppend(sb, SP) }
            if b < rowLen {
                let v = toInt(bufGetByte(buf, i + b))
                let hi = v / 16
                let lo = v - hi * 16
                sb = sbAppend(sb, substring(HEX, hi, hi + 1))
                sb = sbAppend(sb, substring(HEX, lo, lo + 1))
                sb = sbAppend(sb, SP)
            } else {
                sb = sbAppend(sb, SP2 + SP)
            }
            b += 1
        }
        sb = sbAppend(sb, SP)
        // ASCII gutter
        let g = 0
        while g < rowLen {
            let v = toInt(bufGetByte(buf, i + g))
            if v >= 32 {
                if v < 127 { sb = sbAppend(sb, fromCharCode(v + "")) }
                else { sb = sbAppend(sb, DOT) }
            } else {
                sb = sbAppend(sb, DOT)
            }
            g += 1
        }
        sb = sbAppend(sb, CRLF)
        i += 16
    }
    if got >= cap {
        sb = sbAppend(sb, CRLF + "[truncated]" + CRLF)
    }
    emit sbToString(sb)
}


// ── Pure-Krypton path helpers (unchanged from 2.0) ──────────────

func fsBaseName(path) {
    let i = len(path) - 1
    while i >= 0 {
        if path[i] == "\\" { emit substring(path, i + 1, len(path)) }
        if path[i] == "/"  { emit substring(path, i + 1, len(path)) }
        i -= 1
    }
    emit path
}

func fsDirName(path) {
    let i = len(path) - 1
    while i >= 0 {
        if path[i] == "\\" { emit substring(path, 0, i) }
        if path[i] == "/"  { emit substring(path, 0, i) }
        i -= 1
    }
    emit ""
}

func fsJoin(a, b) {
    if len(a) == 0 { emit b }
    if len(b) == 0 { emit a }
    let last = a[len(a) - 1]
    if last == "\\" { emit a + b }
    if last == "/"  { emit a + b }
    emit a + "\\" + b
}

// Test if a name has one of the listed extensions (CSV).
func fsHasExt(name, extCsv) {
    let i = len(name) - 1
    while i >= 0 {
        if name[i] == "." {
            let ext = substring(name, i, len(name))
            if contains("," + extCsv + ",", "," + ext + ",") { emit "1" }
            emit "0"
        }
        i -= 1
    }
    emit "0"
}
