// stdlib/terminal.k — cross-platform terminal control, pure Krypton.
//
// Windows: routes through head:windows + head:conio + head:process — the
// Win32 IAT direct path used elsewhere in 2.0 (gui.k, winio.k pattern).
// No C source, no libc, no runtime DLL additions.
//
// Linux / macOS: not yet implemented. When the Linux ELF backend grows
// the syscall builtins described in docs/linux_x86_2_0_port_plan.txt,
// this module gains a Linux path via direct SYSCALL emission — still no
// libc. Until then, terminal control on Linux is unavailable from pure
// Krypton; affected programs (e.g. ktop) build but stub out their Linux
// platform layer.
//
// API:
//   termEnableVT100()         — enable ANSI escape processing (Windows)
//   termSetRaw()              — disable line buffering + echo, returns saved state
//   termRestore(saved)        — restore the original terminal mode
//   termKbhit()               — "1" if a key is waiting, "0" otherwise
//   termGetch()               — read one key; arrow keys come back as
//                               "UP" / "DOWN" / "PGUP" / "PGDN"; returns ""
//                               on no input or unrecognized escape sequence
//   termSize()                — "<cols>,<rows>" for the active console
//   termSleep(ms)             — sleep for ms milliseconds

module terminal

import "head:windows"
import "head:conio"

// ── Console setup ───────────────────────────────────────────────
//
// VT100 escape sequences require ENABLE_VIRTUAL_TERMINAL_PROCESSING
// (bit 2 = 4) on the output handle. Also flip the console codepage to
// 65001 (UTF-8) so multibyte output renders correctly.
func termEnableVT100() {
    let h = GetStdHandle(toHandle("-11"))
    let mode = structNew("_DWord")
    GetConsoleMode(h, mode)
    let m = toInt(structGet(mode, "_DWord", "val"))
    if m / 4 % 2 == 0 {
        SetConsoleMode(h, toHandle(m + 4 + ""))
    }
    SetConsoleOutputCP(toHandle("65001"))
    emit ""
}

// ── Raw mode ────────────────────────────────────────────────────
//
// On Windows the Win32 console doesn't surface a termios-equivalent
// raw mode in the same way POSIX does — line-buffered cooked input is
// handled at the console level, and _kbhit() / _getch() already bypass
// it. So Windows termSetRaw is a no-op, and termRestore is too. The
// API still returns / accepts a "saved" value so cross-platform code
// can use the same pattern.
func termSetRaw()           { emit "" }
func termRestore(saved)     { emit "" }

// ── Keyboard input ──────────────────────────────────────────────

func termKbhit() {
    emit _kbhit() > 0 ? "1" : "0"
}

// Read one character (or an extended-key escape sequence on the Windows
// console: leading 0x00 or 0xE0 means a function/arrow key follows).
// Returns "" on no input or unrecognized escape.
func termGetch() {
    if _kbhit() == "0" { emit "" }
    let c = toInt(_getch())
    if c == 0 || c == 224 {
        let c2 = toInt(_getch())
        if c2 == 72 { emit "UP" }
        if c2 == 80 { emit "DOWN" }
        if c2 == 73 { emit "PGUP" }
        if c2 == 81 { emit "PGDN" }
        emit ""
    }
    emit fromCharCode(c)
}

// ── Terminal size ──────────────────────────────────────────────

func termSize() {
    let csbi = structNew("CONSOLE_SCREEN_BUFFER_INFO")
    let h = GetStdHandle(toHandle("-11"))
    GetConsoleScreenBufferInfo(h, csbi)
    let l = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowLeft"))
    let r = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowRight"))
    let t = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowTop"))
    let b = toInt(structGet(csbi, "CONSOLE_SCREEN_BUFFER_INFO", "srWindowBottom"))
    let cols = r - l + 1
    let rows = b - t + 1
    if cols <= 0 { cols = 80 }
    if rows <= 0 { rows = 24 }
    emit cols + "," + rows
}

// ── Sleep ─────────────────────────────────────────────────────

func termSleep(ms) {
    Sleep(toHandle(ms))
    emit ""
}
