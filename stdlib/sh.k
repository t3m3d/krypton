// stdlib/sh.k — shell command helpers for KryptScript. PURE KRYPTON, no clang.
//
// Built on the native `exec` builtin (fork/exec via syscall — no C toolchain).
// `exec` returns the command's stdout as a string, WITH a trailing newline,
// so most helpers here trim it for you.
//
//   sh("uname -s")            -> "Darwin"        (trimmed)
//   shRaw("ls")               -> "a\nb\nc\n"     (untrimmed)
//   shOk("test -e /etc")      -> "1" / "0"       (success of the command)
//   which("git")              -> "/usr/bin/git" or ""
//   shLineCount / shLine      -> iterate output lines
//
// Quote arguments with q() when they may contain spaces.

module sh

// native trim() strips spaces only (not \n\r\t), so chomp exec output here.
func _chomp(s) {
    let lo = 0
    let hi = len(s)
    while lo < hi {
        let c = toInt(charCode(s[lo]))
        if c == 32 || c == 9 || c == 10 || c == 13 { lo += 1 } else { break }
    }
    while hi > lo {
        let c = toInt(charCode(s[hi - 1]))
        if c == 32 || c == 9 || c == 10 || c == 13 { hi -= 1 } else { break }
    }
    emit substring(s, lo, hi)
}

// q(s): wrap a string in double quotes for safe use in a command.
func q(s) { emit "\"" + s + "\"" }

// sh(cmd): run cmd, return stdout trimmed of surrounding whitespace.
func sh(cmd) { emit _chomp(exec(cmd)) }

// shRaw(cmd): run cmd, return stdout verbatim (trailing newline kept).
func shRaw(cmd) { emit exec(cmd) }

// shOk(cmd): "1" if the command exits 0, else "0". Output is discarded.
func shOk(cmd) {
    emit _chomp(exec("( " + cmd + " ) >/dev/null 2>&1 && echo 1 || echo 0"))
}

// shLines(cmd): stdout for line iteration via lineCount()/getLine().
// (Returns raw string; use shLineCount/shLine below, or the builtins directly.)
func shLines(cmd) { emit exec(cmd) }
func shLineCount(out) { emit lineCount(out) }
func shLine(out, i)   { emit getLine(out, i) }

// which(name): absolute path of an executable, or "" if not on PATH.
func which(name) { emit _chomp(exec("command -v " + q(name) + " 2>/dev/null")) }

// has(name): "1" if an executable is on PATH, else "0".
func has(name) {
    if which(name) == "" { emit "0" }
    emit "1"
}

// pipe(a, b): run `a | b`, return trimmed stdout. Convenience for clarity.
func pipe(a, b) { emit _chomp(exec(a + " | " + b)) }
