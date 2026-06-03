// stdlib/arch.k — host CPU architecture detection in pure Krypton.
//
// Returns the running platform's CPU architecture as a normalized
// string. Useful for programs that want to branch on host arch
// (select a code path, report platform info, choose a binary).
//
// Implementation: `uname -m` on Linux / macOS, `%PROCESSOR_ARCHITECTURE%`
// on Windows, both via the existing shellRun builtin. No new syscalls,
// no new compiler surface — purely a stdlib module.
//
// Canonical names returned by `arch()`:
//   "x86_64"  — 64-bit Intel/AMD (includes amd64, AMD64)
//   "arm64"   — 64-bit ARM (includes aarch64; both Apple Silicon
//               and Windows-on-ARM)
//   "x86"     — 32-bit Intel (i386, i686)
//   "armv7"   — 32-bit ARM
//   "unknown" — couldn't tell
//
// archRaw() returns the underlying value before normalization (for
// when you want to know "aarch64" vs "arm64" specifically).
//
// Status as of 2026-06-03:
//   Linux x86_64 ✓     macOS arm64 ✓
//   Linux aarch64 ✓ (detection works; the elf.k aarch64 backend is at
//                    M3 — no string concat yet — so most programs that
//                    USE arch() can't run on aarch64 until M4 lands)
//   macOS x86_64 ✓     Windows x86_64 ✓
//   Windows arm64 — detection ready; no compiler backend yet (the
//                   point of shipping this now is to be ready for
//                   that future).
//
// Usage:
//   import "k:arch"
//   just run {
//       let a = arch()
//       print("running on " + a)
//       if isArm() { print("ARM path") } else { print("x86 path") }
//   }

module arch

// arch() -> canonical name. See header for the value set.
func arch() {
    emit _normalize(_rawArch())
}

// archRaw() -> the raw `uname -m` / `PROCESSOR_ARCHITECTURE` value,
// without normalization. Trailing whitespace stripped.
func archRaw() { emit _rawArch() }

// is64Bit() -> 1 if arch is x86_64 or arm64, else 0.
func is64Bit() {
    let a = arch()
    if a == "x86_64" { emit 1 }
    if a == "arm64"  { emit 1 }
    emit 0
}

// isArm() -> 1 on ARM (Apple Silicon, Windows-on-ARM, Linux aarch64).
func isArm() {
    if arch() == "arm64" { emit 1 }
    if arch() == "armv7" { emit 1 }
    emit 0
}

// isX86() -> 1 on x86_64 / AMD64, else 0.
func isX86() {
    if arch() == "x86_64" { emit 1 }
    emit 0
}

// ── internals ─────────────────────────────────────────────────────────
// _rawArch() -> trimmed arch string from the first source that gives
// a recognisable answer. Order matters — most reliable per-platform
// path first. shellRun is NOT used: on the Linux backend it
// inherits stdio and prints to the terminal instead of capturing.
//
// 1. /proc/sys/kernel/arch  — Linux only, kernel-truth, no env deps.
// 2. PROCESSOR_ARCHITECTURE — Windows, set by the OS in every shell.
// 3. HOSTTYPE               — bash everywhere (Linux + macOS + git
//                              bash on Windows). Covers macOS where
//                              there's no /proc.
// 4. CPUTYPE                — zsh fallback (macOS default shell). Some
//                              setups set it instead of HOSTTYPE.
func _rawArch() {
    let p = _trimTail(_firstLine(readProc("/proc/sys/kernel/arch")))
    if _looksLikeArch(p) { emit p }

    let w = _trimTail(environ("PROCESSOR_ARCHITECTURE"))
    if _looksLikeArch(w) { emit w }

    let h = _trimTail(environ("HOSTTYPE"))
    if _looksLikeArch(h) { emit h }

    let c = _trimTail(environ("CPUTYPE"))
    if _looksLikeArch(c) { emit c }

    emit ""
}

// _looksLikeArch(s) -> 1 if `s` matches a known arch token. Filters
// out shell error messages like "uname: command not found" and the
// literal "%PROCESSOR_ARCHITECTURE%" you get from `echo` on bash.
func _looksLikeArch(s) {
    let n = _toLower(s)
    if n == "x86_64"  { emit 1 }
    if n == "amd64"   { emit 1 }
    if n == "aarch64" { emit 1 }
    if n == "arm64"   { emit 1 }
    if n == "i686"    { emit 1 }
    if n == "i386"    { emit 1 }
    if n == "x86"     { emit 1 }
    if n == "armv7l"  { emit 1 }
    if n == "armv7"   { emit 1 }
    emit 0
}

// _normalize(raw) -> canonical name.
func _normalize(raw) {
    let s = _toLower(raw)
    if s == "x86_64"  { emit "x86_64" }
    if s == "amd64"   { emit "x86_64" }
    if s == "aarch64" { emit "arm64" }
    if s == "arm64"   { emit "arm64" }
    if s == "i686"    { emit "x86" }
    if s == "i386"    { emit "x86" }
    if s == "x86"     { emit "x86" }
    if s == "armv7l"  { emit "armv7" }
    if s == "armv7"   { emit "armv7" }
    emit "unknown"
}

// _firstLine(s) -> everything before the first \n, or all of s if no \n.
func _firstLine(s) {
    let n = indexOf(s, fromCharCode(10))
    if n >= 0 { emit substring(s, 0, n) }
    emit s
}

// _trimTail(s) -> drop trailing whitespace (NL/CR/TAB/SP).
func _trimTail(s) {
    let n = len(s)
    while n > 0 {
        let c = charCode(s[n - 1])
        if c > 32 { emit substring(s, 0, n) }
        n -= 1
    }
    emit ""
}

// _toLower(s) -> ASCII lowercase.
func _toLower(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let c = charCode(s[i])
        if c >= 65 && c <= 90 { c = c + 32 }
        out = out + fromCharCode(c)
        i += 1
    }
    emit out
}
