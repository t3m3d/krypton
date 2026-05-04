// dashboard.k — live system dashboard with Python-frontend-quality polish
//
// Compile (Windows, C path — needs gcc):
//   kcc.exe --headers headers/ examples/dashboard.k > tmp.c
//   gcc tmp.c -o dashboard.exe -lpsapi -lpdh -lshell32 -ladvapi32 -lm -w
//   .\dashboard.exe
//
// Renders a polished top-style live monitor with memory, disk, and
// session stats, refreshed once per second. Uses ANSI escape codes for
// layout, box-drawing characters for panel borders, colour-graded
// progress bars.
//
// Why C path and not native PE: the Windows native pipeline (`kcc.sh
// --native`) has known gaps that this program would hit:
//   - `sbAppend` / `sbToString` segfault inside tight loops on Windows
//     native (Linux ELF works); the bar-drawing loop here triggers it
//   - `repeat` builtin is Linux-ELF only on the native side
//   - `GetTickCount64` returns UINT64 that exceeds the smart-int
//     boundary (0x40000000) on long-uptime machines and gets
//     re-interpreted as a heap pointer
// All three are 1.6 / Tier 1 items (see docs/roadmap.md). The C-emit
// path has none of them.
//
// Best viewed in Windows Terminal, PowerShell 7, or modern cmd.exe.
// Press Ctrl+C to exit.

import "windows.krh"
import "process.krh"

// ── ANSI helpers ──────────────────────────────────────────────────

func ansiClear() { kp("\x1b[2J\x1b[H") }
func ansiHome()  { kp("\x1b[H") }
func ansiHide()  { kp("\x1b[?25l") }
func ansiShow()  { kp("\x1b[?25h") }

func paint(code, s) { emit "\x1b[" + code + "m" + s + "\x1b[0m" }
func cyan(s)        { emit paint("38;5;87", s) }
func green(s)       { emit paint("38;5;78", s) }
func yellow(s)      { emit paint("38;5;221", s) }
func red(s)         { emit paint("38;5;203", s) }
func dim(s)         { emit paint("38;5;240", s) }
func text(s)        { emit paint("38;5;252", s) }
func accent(s)      { emit paint("1;38;5;81", s) }

// ── Format helpers ────────────────────────────────────────────────

func padL(s, n) {
    let out = s + ""
    while len(out) < toInt(n) { out = " " + out }
    emit out
}

func padR(s, n) {
    let out = s + ""
    while len(out) < toInt(n) { out = out + " " }
    emit out
}

// String-builder repeat — bypasses the smart-int "digit-only concat"
// trap and works in the Windows native pipeline (`repeat` builtin is
// Linux ELF only today).
func srepeat(ch, n) {
    let sb = sbNew()
    let i = 0
    while i < toInt(n) {
        sb = sbAppend(sb, ch)
        i += 1
    }
    emit sbToString(sb)
}

// 0–100 percent → coloured bar of given width. Green / yellow / red as
// load rises.
func bar(percent, width) {
    let p = toInt(percent)
    let w = toInt(width)
    if p < 0 { p = 0 }
    if p > 100 { p = 100 }
    let filled = p * w / 100
    let empty  = w - filled

    let body = srepeat("█", filled) + srepeat("░", empty)
    if p < 60 { emit green(body) }
    if p < 85 { emit yellow(body) }
    emit red(body)
}

func bytesToGB(b)    { emit toInt(b) / 1073741824 + "" }

// Format an integer second-count → "Xh Ym Zs". Krypton-side counter,
// so always smart-int safe (vs. GetTickCount64 which can exceed
// 0x40000000 and get re-interpreted as a heap pointer).
func formatElapsed(secs) {
    let s = toInt(secs)
    let hrs  = s / 3600
    s = s - hrs * 3600
    let mins = s / 60
    s = s - mins * 60
    emit padL(hrs + "", 2) + "h " + padL(mins + "", 2) + "m " + padL(s + "", 2) + "s"
}

// ── Sample collectors ────────────────────────────────────────────
//
// Memory + disk sizes come back as 64-bit byte counts that don't fit
// in a 32-bit `toInt()`. We pre-divide by 1 GiB on the C side using
// the `div64` builtin so the values fit, then do the percent math in
// regular 32-bit Krypton.

func GIB() { emit "1073741824" }

func sampleMem() {
    let ms = structNew("MEMORYSTATUSEX")
    structSet(ms, "MEMORYSTATUSEX", "dwLength", sizeOf("MEMORYSTATUSEX"))
    GlobalMemoryStatusEx(ms)
    let totalGB = toInt(div64(structGet(ms, "MEMORYSTATUSEX", "ullTotalPhys"), GIB()))
    let availGB = toInt(div64(structGet(ms, "MEMORYSTATUSEX", "ullAvailPhys"), GIB()))
    let usedGB  = totalGB - availGB
    let pct     = usedGB * 100 / totalGB
    emit totalGB + "|" + usedGB + "|" + pct
}

func sampleDisk(root) {
    let free    = structNew("ULARGE_INTEGER")
    let total   = structNew("ULARGE_INTEGER")
    let allFree = structNew("ULARGE_INTEGER")
    GetDiskFreeSpaceExA(root, free, total, allFree)
    let totalGB = toInt(div64(structGet(total,   "ULARGE_INTEGER", "QuadPart"), GIB()))
    let freeGB  = toInt(div64(structGet(allFree, "ULARGE_INTEGER", "QuadPart"), GIB()))
    let usedGB  = totalGB - freeGB
    let pct     = usedGB * 100 / totalGB
    emit totalGB + "|" + usedGB + "|" + pct
}

func sampleCpu() {
    let si = structNew("SYSTEM_INFO")
    GetNativeSystemInfo(si)
    let n = structGet(si, "SYSTEM_INFO", "dwNumberOfProcessors")
    emit n
}

func part(s, idx) {
    let cur = s
    let i = 0
    while i < toInt(idx) {
        let p = indexOf(cur, "|")
        if p < 0 { emit "" }
        cur = substring(cur, p + 1, len(cur))
        i += 1
    }
    let p = indexOf(cur, "|")
    if p < 0 { emit cur }
    emit substring(cur, 0, p)
}

// ── Layout primitives (60-column boxed panels) ────────────────────

func line(s)  { kp("  " + dim("│ ") + s + dim(" │")) }
func sep()    { kp("  " + dim("├" + srepeat("─", 60) + "┤")) }

func boxTop(title) {
    let lhs = "─── " + accent(title) + " "
    let visible = 4 + len(title) + 1            // "─── " + title + " "
    let rhs = srepeat("─", 60 - visible)
    kp("  " + dim("┌") + dim(lhs) + dim(rhs) + dim("┐"))
}

func boxBot() {
    kp("  " + dim("└" + srepeat("─", 60) + "┘"))
}

// ── Frame ─────────────────────────────────────────────────────────

func renderStat(label, pct, used, total, unit) {
    // Label (10 wide) + bar (30 wide) + spacer + value column
    let lbl = padR(label, 10)
    let val = padL(used, 5) + " " + dim("/") + " " + padL(total, 5) + " " + unit + "  " + padL(pct + "", 3) + "%"
    line(text(lbl) + bar(pct, 30) + "  " + text(val))
}

func renderFrame(elapsedSec, cpus) {
    let mem  = sampleMem()
    let disk = sampleDisk("C:\\")

    let memTotal  = part(mem,  "0")
    let memUsed   = part(mem,  "1")
    let memPct    = part(mem,  "2")

    let diskTotal = part(disk, "0")
    let diskUsed  = part(disk, "1")
    let diskPct   = part(disk, "2")

    ansiHome()

    // Header
    kp("")
    kp("  " + accent("KRYPTON") + dim("  ╱  ") + text("live dashboard") + dim("  ╱  ") + dim("auto-refresh 1s"))
    kp("")

    // System box
    boxTop("System")
    line(text("CPU cores ") + cyan(padL(cpus, 3)) + dim("  ·  ") + text("uptime  ") + cyan(formatElapsed(elapsedSec)))
    boxBot()
    kp("")

    // Resources box
    boxTop("Resources")
    renderStat("Memory", memPct, memUsed, memTotal, "GB")
    line("")
    renderStat("Disk C:", diskPct, diskUsed, diskTotal, "GB")
    boxBot()
    kp("")

    // Footer hint
    kp("  " + dim("Krypton 1.5.1  ·  refresh 1s  ·  press Ctrl+C to exit            "))
    kp("")
}

just run {
    let cpus = sampleCpu()
    ansiClear()
    ansiHide()
    let frames = 0
    while frames < 600 {
        renderFrame(frames, cpus)
        Sleep("1000")
        frames += 1
    }
    ansiShow()
    emit 0
}
