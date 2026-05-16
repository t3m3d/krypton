import "head:fileio"

func ansi(s) {
    let esc = fromCharCode(27)
    emit replace(s, "\\x1b", esc)
}

func vislen(s) {
    let total = len(s)
    let vis = "0"
    let i = "0"
    let esc = fromCharCode(27)
    while toInt(i) < toInt(total) {
        let ch = substring(s, toInt(i), toInt(i) + 1)
        if ch == esc {
            i = toInt(i) + 1 + ""
            while toInt(i) < toInt(total) {
                let c2 = substring(s, toInt(i), toInt(i) + 1)
                i = toInt(i) + 1 + ""
                if c2 == "m" { break }
            }
        } else {
            vis = toInt(vis) + 1 + ""
            i = toInt(i) + 1 + ""
        }
    }
    emit vis
}

func padansi(s, w) {
    let vl = toInt(vislen(s))
    let pad = toInt(w) - vl
    let result = s
    let i = "0"
    while toInt(i) < pad {
        result = result + " "
        i = toInt(i) + 1 + ""
    }
    emit result
}

func firstpart(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit s }
    emit substring(s, 0, toInt(pos))
}

func afterpart(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit "" }
    emit substring(s, toInt(pos) + 1, len(s))
}

func linecount(s) {
    if s == "" { emit "0" }
    let t = trim(s)
    if t == "" { emit "0" }
    let n = "1"
    let i = "0"
    while toInt(i) < len(t) {
        let ch = substring(t, toInt(i), toInt(i) + 1)
        if ch == "\n" { n = toInt(n) + 1 + "" }
        i = toInt(i) + 1 + ""
    }
    emit n
}

func nthline(s, lineIdx) {
    let target = toInt(lineIdx)
    let cur = "0"
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(s, toInt(start), len(s))
        let nlPos = indexOf(rest, "\n")
        if nlPos < 0 {
            if toInt(cur) == target { emit trim(rest) }
            done = "1"
        } else {
            if toInt(cur) == target {
                emit trim(substring(rest, 0, toInt(nlPos)))
            }
            start = toInt(start) + toInt(nlPos) + 1 + ""
            cur = toInt(cur) + 1 + ""
        }
    }
    emit ""
}

func rambar(usedMB, totalMB) {
    let used  = toInt(usedMB)
    let total = toInt(totalMB)
    if total == 0 { emit "[                    ]" }
    let pct    = used * 100 / total
    let filled = pct * 20 / 100
    let empty  = 20 - filled
    let bar    = "["
    let i = 0
    while i < filled { bar = bar + "▒"  i += 1 }
    i = 0
    while i < empty  { bar = bar + "█"  i += 1 }
    emit bar + "]"
}

func colorpalette() {
    let E   = fromCharCode(27)
    let RST = E + "[0m"
    let blk = "   "
    let r1  = ""
    let r2  = ""
    let i   = "0"
    while toInt(i) < 8 {
        let c1 = toInt(i) + 40 + ""
        let c2 = toInt(i) + 100 + ""
        r1 = r1 + E + "[" + c1 + "m" + blk
        r2 = r2 + E + "[" + c2 + "m" + blk
        i = toInt(i) + 1 + ""
    }
    kp("  " + r1 + RST)
    kp("  " + r2 + RST)
}

func idxfrom(s, sub, start) {
    let slen = len(s)
    let sublen = len(sub)
    let i = toInt(start)
    while toInt(i) <= toInt(slen) - toInt(sublen) {
        let piece = substring(s, toInt(i), toInt(i) + toInt(sublen))
        if piece == sub { emit i + "" }
        i = toInt(i) + 1 + ""
    }
    emit "-1"
}

func countRegSubkeys(hive, path) {
    // 2.0: phResult is a buffer; extract HKEY via bufGetQword(phResult,0).
    let kread = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(hive, path, "0", kread, phResult)
    if r != "0" { emit "0" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("256")
    let sz  = bufNew("4")
    let cnt = "0"
    let idx = "0"
    while toInt(idx) < 65536 {
        bufSetDword(sz, "256")
        let er = RegEnumKeyExA(hk, idx, buf, sz, toHandle("0"), toHandle("0"), toHandle("0"), toHandle("0"))
        if er != "0" { break }
        cnt = toInt(cnt) + 1 + ""
        idx = toInt(idx) + 1 + ""
    }
    RegCloseKey(hk)
    emit cnt
}

func countDirs(path) {
    // 2.0: GetFileAttributesA + FindFirstFileA + FindNextFileA all itoa'd.
    let attrs = GetFileAttributesA(path)
    // INVALID_FILE_ATTRIBUTES = (DWORD)-1 = 4294967295
    if attrs == "4294967295" { emit "0" }
    if attrs == "-1" { emit "0" }
    if bitAnd(attrs, "16") == "0" { emit "0" }
    let fd  = structNew("WIN32_FIND_DATAA")
    let h   = FindFirstFileA(path + "\\*", fd)
    if h == "0" { emit "0" }
    // INVALID_HANDLE_VALUE = (HANDLE)-1 = 18446744073709551615
    if h == "18446744073709551615" { emit "0" }
    let cnt = "0"
    let di  = "0"
    while toInt(di) < 65536 {
        let fa   = structGet(fd, "WIN32_FIND_DATAA", "dwFileAttributes")
        let name = structGet(fd, "WIN32_FIND_DATAA", "cFileName")
        if bitAnd(fa, "16") != "0" {
            if name != "." {
                if name != ".." {
                    cnt = toInt(cnt) + 1 + ""
                }
            }
        }
        let nxt = FindNextFileA(h, fd)
        if nxt == "0" { break }
        di = toInt(di) + 1 + ""
    }
    FindClose(h)
    emit cnt
}

func kfpkgs() {
    let HKLM = "2147483650"
    let HKCU = "2147483649"
    let p1 = countRegSubkeys(HKLM, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall")
    let p2 = countRegSubkeys(HKLM, "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall")
    let p3 = countRegSubkeys(HKCU, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall")
    let winget = toInt(p1) + toInt(p2) + toInt(p3) + ""

    let scoopPath = environ("USERPROFILE") + "\\scoop\\apps"
    let scoopRaw  = countDirs(scoopPath)
    let scoop     = toInt(scoopRaw) - 1 + ""
    if toInt(scoop) < 0 { scoop = "0" }

    let chocoBase = environ("ChocolateyInstall")
    if chocoBase == "" { chocoBase = regHklmStr("SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", "ChocolateyInstall") }
    let choco = "0"
    if chocoBase != "" {
        let chocoLib = chocoBase + "\\lib"
        choco = countDirs(chocoLib)
    }

    let result = ""
    if toInt(winget) > 0 { result = winget + " (winget)" }
    if toInt(scoop) > 0 {
        if result != "" { result = result + ", " }
        result = result + scoop + " (scoop)"
    }
    if toInt(choco) > 0 {
        if result != "" { result = result + ", " }
        result = result + choco + " (choco)"
    }
    emit result
}

// ── Krypton registry helpers ──────────────────────────────────────────
// 2.0: Reg* functions are Win32-marshalled in x64.k. Int args (hKey,
// ulOptions, samDesired) go as plain strings — atoi happens at the call
// site. NULL POINTER args (e.g. RegQueryValueExA's lpReserved/lpType)
// still need toHandle("0") to be raw int 0 — passing string "0" would
// give Win32 a pointer to "0\0" which it would then DEREFERENCE and
// WRITE OUT through, corrupting the Krypton arena.
// 2.0 ABI: phResult = bufNew(8) — Win32 writes HKEY into the byte buffer,
// then bufGetQword extracts it as an int. Avoid handleOut/handleGet (1.x
// raw-pointer convention incompatible with marshalled call sites). NULL
// pointer args use toHandle("0") so they go through as raw int 0, not as
// pointers to a "0\0" string (which Win32 would dereference and write to).
func regHklmStr(path, name) {
    let HKLM     = "2147483650"
    let kread    = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKLM, path, "0", kread, phResult)
    if r != "0" { emit "" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("1024")
    let sz  = bufNew("4")
    bufSetDword(sz, "1024")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufStr(buf)
}

func regHkcuStr(path, name) {
    let HKCU     = "2147483649"
    let kread    = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKCU, path, "0", kread, phResult)
    if r != "0" { emit "" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("1024")
    let sz  = bufNew("4")
    bufSetDword(sz, "1024")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufStr(buf)
}

func regHklmDword(path, name) {
    let HKLM     = "2147483650"
    let kread    = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKLM, path, "0", kread, phResult)
    if r != "0" { emit "0" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("4")
    let sz  = bufNew("4")
    bufSetDword(sz, "4")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufGetDword(buf)
}

func regHkcuDword(path, name) {
    let HKCU     = "2147483649"
    let kread    = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKCU, path, "0", kread, phResult)
    if r != "0" { emit "0" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("4")
    let sz  = bufNew("4")
    bufSetDword(sz, "4")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufGetDword(buf)
}

func regHklmQword(path, name) {
    let HKLM     = "2147483650"
    let kread    = "131097"
    let phResult = bufNew("8")
    let r = RegOpenKeyExA(HKLM, path, "0", kread, phResult)
    if r != "0" { emit "0" }
    let hk  = bufGetQword(phResult)
    let buf = bufNew("8")
    let sz  = bufNew("4")
    bufSetDword(sz, "8")
    RegQueryValueExA(hk, name, toHandle("0"), toHandle("0"), buf, sz)
    RegCloseKey(hk)
    emit bufGetQword(buf)
}

