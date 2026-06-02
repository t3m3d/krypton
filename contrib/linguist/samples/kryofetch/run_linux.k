// kryofetch — Linux (x86-64 / aarch64) edition. Pure Krypton, native backend.
//
// Sibling to run.k (Windows, Win32 API) and run_macos.k (macOS, sysctl/
// system_profiler). The Linux native backend (compiler/linux_x86/elf.k) does
// not implement exec()/environ() (they no-op), and readFile() can't read the
// /proc & /sys virtual files (their st_size is 0). So this edition uses the
// native `readProc(path)` builtin — inline open+read-loop+close syscalls,
// added to elf.k alongside the socket builtins — to slurp /proc, /sys and
// /etc, then parses the text with the standard string builtins.
//
//   kcc.sh -r run_linux.k          compile + run
//   kcc.sh -r run_linux.k --watch  re-render every second
//
// Self-contained on purpose: the native backend doesn't link nested module
// imports transitively. Built and verified on ParrotOS / Debian. Any field
// that can't be read is simply omitted.

// ── generic string / render helpers (mirrors utils_macos.k) ──────────────
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

func infoline(s, lineIdx) {
    let target = toInt(lineIdx)
    let cur = "0"
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(s, toInt(start), len(s))
        let nlPos = indexOf(rest, "\n")
        if nlPos < 0 {
            if toInt(cur) == target { emit rest }
            done = "1"
        } else {
            if toInt(cur) == target { emit substring(rest, 0, toInt(nlPos)) }
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

// ── /proc + /etc parsing helpers ─────────────────────────────────────────
// First line of text `s` whose start matches `key` (whole line returned).
func findLine(s, key) {
    let n = toInt(linecount(s))
    let i = 0
    while i < n {
        let ln = getLine(s, i)
        if startsWith(ln, key) { emit ln }
        i = i + 1
    }
    emit ""
}

// Text after the first ':' in `s`, trimmed (for "key: value" /proc lines).
func afterColon(s) {
    let p = indexOf(s, ":")
    if p < 0 { emit trim(s) }
    emit trim(substring(s, toInt(p) + 1, len(s)))
}

// Count lines beginning with `key`.
func countPrefix(s, key) {
    let n = toInt(linecount(s))
    let i = 0
    let c = 0
    while i < n {
        if startsWith(getLine(s, i), key) { c = c + 1 }
        i = i + 1
    }
    emit c + ""
}

// nth `delim`-separated field of `s` (0-based). Avoids split() (broken native).
func nthField(s, delim, n) {
    let cur = s
    let i = 0
    while i < n {
        cur = afterpart(cur, delim)
        i = i + 1
    }
    emit firstpart(cur, delim)
}

// ── system info collectors (Linux, via readProc / readFile) ──────────────
func osver() {
    let r = readFile("/etc/os-release")          // real file: readFile works
    let line = findLine(r, "PRETTY_NAME=")
    if line != "" {
        let v = afterpart(line, "=")
        if startsWith(v, "\"") { v = substring(v, 1, len(v)) }
        if endsWith(v, "\"")   { v = substring(v, 0, len(v) - 1) }
        emit v
    }
    emit "Linux"
}

func syshost() {
    let h = trim(readProc("/proc/sys/kernel/hostname"))
    if h != "" { emit h }
    let h2 = trim(readFile("/etc/hostname"))
    if h2 != "" { emit h2 }
    emit "localhost"
}

func kfkernel() {
    let osr = trim(readProc("/proc/sys/kernel/osrelease"))
    if osr == "" { emit "Linux" }
    emit "Linux " + osr
}

func sysarch() {
    let osr = readProc("/proc/sys/kernel/osrelease")
    if contains(osr, "amd64") { emit "x86_64" }
    if contains(osr, "arm64") { emit "aarch64" }
    if contains(osr, "686")   { emit "x86" }
    emit ""
}

func sysmodel() {
    let m = trim(readProc("/sys/devices/virtual/dmi/id/product_name"))
    if m == "To be filled by O.E.M." { emit "" }
    if m == "System Product Name"    { emit "" }
    emit m
}

func cpubrand() {
    let ci = readProc("/proc/cpuinfo")
    let ln = findLine(ci, "model name")
    if ln != "" { emit afterColon(ln) }
    let hw = findLine(ci, "Hardware")          // some ARM boards
    if hw != "" { emit afterColon(hw) }
    let mp = findLine(ci, "Model")
    if mp != "" { emit afterColon(mp) }
    emit "Unknown CPU"
}

// logical thread count = number of "processor" lines in /proc/cpuinfo.
func cputhreads() {
    let ci = readProc("/proc/cpuinfo")
    let n = countPrefix(ci, "processor")
    if n == "0" { emit "1" }
    emit n
}

// "totalMB,availMB" from /proc/meminfo (values are in kB).
func raminfo() {
    let mi = readProc("/proc/meminfo")
    let tl = findLine(mi, "MemTotal:")
    let al = findLine(mi, "MemAvailable:")
    if tl == "" { emit "0,0" }
    let tkb = toInt(firstpart(afterColon(tl), " "))
    let akb = toInt(firstpart(afterColon(al), " "))
    emit (tkb / 1024) + "," + (akb / 1024)
}

func swapinfo() {
    let mi = readProc("/proc/meminfo")
    let tl = findLine(mi, "SwapTotal:")
    let fl = findLine(mi, "SwapFree:")
    if tl == "" { emit "Unused" }
    let tkb = toInt(firstpart(afterColon(tl), " "))
    let fkb = toInt(firstpart(afterColon(fl), " "))
    if tkb == 0 { emit "Unused" }
    let ukb = tkb - fkb
    emit (ukb / 1024) + " MB used / " + (tkb / 1024) + " MB total"
}

func uptimestr() {
    let raw = trim(readProc("/proc/uptime"))
    if raw == "" { emit "unknown" }
    let secs = toInt(firstpart(firstpart(raw, " "), "."))
    let d = secs / 86400
    let h = (secs - d * 86400) / 3600
    let m = (secs - d * 86400 - h * 3600) / 60
    if d > 0 { emit d + "d " + h + "h " + m + "m" }
    if h > 0 { emit h + "h " + m + "m" }
    emit m + "m"
}

// Username + login shell WITHOUT environ/exec: real uid from /proc/self/status,
// then resolve it against /etc/passwd (a real, readFile-able file).
func _uid() {
    let st = readProc("/proc/self/status")
    let ul = findLine(st, "Uid:")
    if ul == "" { emit "" }
    // "Uid:\t<real>\t<eff>\t..." — take field 1 split on TAB (trim() leaves tabs).
    emit nthField(ul, "\t", 1)
}

func _passwdLine() {
    let uid = _uid()
    if uid == "" { emit "" }
    let pw = readFile("/etc/passwd")
    let n = toInt(linecount(pw))
    let i = 0
    while i < n {
        let ln = getLine(pw, i)
        if nthField(ln, ":", 2) == uid { emit ln }
        i = i + 1
    }
    emit ""
}

func sysuser() {
    let ln = _passwdLine()
    if ln != "" {
        let u = nthField(ln, ":", 0)
        if u != "" { emit u }
    }
    emit "user"
}

func kfshell() {
    let ln = _passwdLine()
    if ln != "" {
        let sh = nthField(ln, ":", 6)
        if sh != "" {
            // basename of the shell path
            let b = sh
            let p = indexOf(b, "/")
            while p >= 0 {
                b = substring(b, toInt(p) + 1, len(b))
                p = indexOf(b, "/")
            }
            emit b
        }
    }
    emit "unknown"
}

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

func run() {
    kfcls()

    let E   = fromCharCode(27)
    let GRN = E + "[32;1m"
    let CYN = E + "[36;1m"
    let RST = E + "[0m"
    let YEL = E + "[33;1m"
    let WHT = E + "[37;1m"
    let LW  = "42"

    // Tux — the Linux mascot.
    let l0  = WHT + "         a8888b." + RST
    let l1  = WHT + "        d888888b." + RST
    let l2  = WHT + "        8P\"YP\"Y88" + RST
    let l3  = WHT + "        8|o||o|88" + RST
    let l4  = WHT + "        8" + YEL + "'    " + WHT + ".88" + RST
    let l5  = WHT + "        8" + YEL + "`._.'" + WHT + " Y8." + RST
    let l6  = WHT + "       d/      `8b." + RST
    let l7  = WHT + "      dP   .    Y8b." + RST
    let l8  = WHT + "     d8:'  \"  `::88b." + RST
    let l9  = WHT + "    d8\"         'Y88b" + RST
    let l10 = WHT + "   :8P    '      :888" + RST
    let l11 = WHT + "    8a.   :     _a88P" + RST
    let l12 = YEL + "  ._/\"Yaa_ :    .| 88P|" + RST
    let l13 = YEL + "  \\    YP\"      `| 8P  `." + RST
    let l14 = YEL + "  /     \\._____.d|    .'" + RST
    let l15 = YEL + "  `--..__)888888P`._.'" + RST

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let kern = kfkernel()
    let mdl  = sysmodel()
    let cpu  = cpubrand()
    let tn   = cputhreads()

    let mi   = raminfo()
    let tmb  = firstpart(mi, ",")
    let amb  = afterpart(mi, ",")
    let umb  = toInt(tmb) - toInt(amb) + ""
    let tgb  = toInt(tmb) / 1024 + ""
    let ugb  = toInt(umb) / 1024 + ""
    let rpct = "0"
    if toInt(tmb) > 0 { rpct = toInt(umb) * 100 / toInt(tmb) + "" }
    let rb   = rambar(umb, tmb)
    let swp  = swapinfo()

    let up   = uptimestr()
    let sh   = kfshell()

    // Build the packed info column — only non-empty fields are added.
    let IL = ""
    IL = IL + GRN + "User:  " + RST + usr + "@" + host + "\n"
    let osline = os
    if arch != "" { osline = osline + " " + arch }
    IL = IL + GRN + "OS:    " + RST + osline + "\n"
    if mdl != "" { IL = IL + GRN + "Host:  " + RST + mdl + "\n" }
    IL = IL + GRN + "Kernel:" + RST + kern + "\n"
    IL = IL + GRN + "CPU:   " + RST + cpu + " (" + tn + "t)\n"
    IL = IL + GRN + "RAM:   " + RST + rb + "  " + ugb + " GB / " + tgb + " GB  " + rpct + "%\n"
    if swp != "Unused" { IL = IL + GRN + "Swap:  " + RST + swp + "\n" }
    IL = IL + GRN + "Shell: " + RST + sh + "\n"
    IL = IL + GRN + "Uptime:" + RST + up + "\n"

    let idx = "0"
    let infolen = linecount(IL)
    let maxidx = "16"
    if toInt(infolen) > 16 { maxidx = infolen }
    while toInt(idx) < toInt(maxidx) {
        let logo = ""
        if idx == "0"  { logo = l0  }
        if idx == "1"  { logo = l1  }
        if idx == "2"  { logo = l2  }
        if idx == "3"  { logo = l3  }
        if idx == "4"  { logo = l4  }
        if idx == "5"  { logo = l5  }
        if idx == "6"  { logo = l6  }
        if idx == "7"  { logo = l7  }
        if idx == "8"  { logo = l8  }
        if idx == "9"  { logo = l9  }
        if idx == "10" { logo = l10 }
        if idx == "11" { logo = l11 }
        if idx == "12" { logo = l12 }
        if idx == "13" { logo = l13 }
        if idx == "14" { logo = l14 }
        if idx == "15" { logo = l15 }
        kp(padansi(logo, toInt(LW)) + "  " + infoline(IL, idx))
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    kp(CYN + "  KryoFetch" + RST + " by KryptonBytes")
    kp("")
    colorpalette()
    kp("")
    emit
}

just run {
    let watch = "0"
    let intervalSec = "1"
    let argc = argCount()
    let i = "0"
    while toInt(i) < toInt(argc) {
        let a = arg(i)
        if a == "--watch" {
            watch = "1"
            if toInt(i) + 1 < toInt(argc) { intervalSec = arg(toInt(i) + 1 + "") }
        }
        i = toInt(i) + 1 + ""
    }

    if watch == "0" {
        run()
    } else {
        while watch == "1" {
            run()
            gcCollect()
        }
    }
}
