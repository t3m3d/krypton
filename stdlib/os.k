// stdlib/os.k -- Python `os` module surface on existing Krypton
// builtins.  Named with the `*k` suffix convention (matches builtins.k
// + string.k + list.k + dict.k + sys.k).
//
// FE lowering:
//   os.getcwd()              -> osgetcwdk()
//   os.environ.get(k, d)     -> osgetenvk(k, d)
//   os.environ[k]            -> osgetenvk(k, "")
//   os.path.join(a, b)       -> ospathjoink(a, b)
//   os.path.exists(p)        -> ospathexistsk(p)
//   os.path.basename(p)      -> ospathbasenamek(p)
//   os.path.dirname(p)       -> ospathdirnamek(p)
//   os.path.splitext(p)      -> ospathsplitextk(p)
//   os.listdir(p)            -> oslistdirk(p)
//   os.mkdir(p)              -> osmkdirk(p)
//   os.remove(p)             -> osremovek(p)
//   os.rename(a, b)          -> osrenamek(a, b)
//   os.sep                   -> ossepk()
//   os.system(cmd)           -> ossystemk(cmd)

module os


// os.getcwd() -- Krypton's `getCwd()` builtin if present; else shell
// out.  Today: shell out via `cd` (Windows) / `pwd` (POSIX).
func osgetcwdk() {
    let cwd = exec("cd")
    let i = len(cwd)
    while i > 0 {
        let c = cwd[i - 1]
        if c == "\r" || c == "\n" { i -= 1 } else { break }
    }
    emit substring(cwd, 0, i)
}

// os.environ.get(key, default)
func osgetenvk(key, default) {
    let v = exec("echo %" + key + "%")
    let i = len(v)
    while i > 0 {
        let c = v[i - 1]
        if c == "\r" || c == "\n" { i -= 1 } else { break }
    }
    let trimmed = substring(v, 0, i)
    // exec("echo %FOO%") returns "%FOO%" literally if unset on Windows.
    if trimmed == "%" + key + "%" { emit default }
    emit trimmed
}


// ── os.path.* ─────────────────────────────────────────────────────────

// os.sep -- platform separator.  Today: hard-code "\\" since this file
// ships under the Windows backend; a per-backend override will adjust.
func ossepk() {
    emit "\\"
}

// os.path.join(a, b)
func ospathjoink(a, b) {
    if a == "" { emit b }
    if b == "" { emit a }
    let sep = ossepk()
    let lastA = a[len(a) - 1]
    if lastA == sep || lastA == "/" { emit a + b }
    emit a + sep + b
}

// os.path.exists(p) -- shell-out probe via Windows `if exist`.
func ospathexistsk(p) {
    let r = exec("if exist \"" + p + "\" (echo y) else (echo n)")
    if indexOf(r, "y") >= 0 { emit 1 }
    emit 0
}

// os.path.basename(p) -- filename component after the last separator.
func ospathbasenamek(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        let c = p[i]
        if c == "\\" || c == "/" { emit substring(p, i + 1, n) }
        i -= 1
    }
    emit p
}

// os.path.dirname(p) -- everything before the last separator.
func ospathdirnamek(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        let c = p[i]
        if c == "\\" || c == "/" { emit substring(p, 0, i) }
        i -= 1
    }
    emit ""
}

// os.path.splitext(p) -- (root, ext) where ext includes the dot.
// Returns "root,ext".
func ospathsplitextk(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        let c = p[i]
        if c == "\\" || c == "/" { break }
        if c == "." {
            emit substring(p, 0, i) + "," + substring(p, i, n)
        }
        i -= 1
    }
    emit p + ","
}


// ── Directory / file ops ──────────────────────────────────────────────

// os.listdir(p) -- comma-list of entries.  Windows `dir /b`.
func oslistdirk(p) {
    let out = sbNew()
    let raw = exec("dir /b \"" + p + "\"")
    let n = len(raw)
    let i = 0
    let lo = 0
    let first = "1"
    while i < n {
        let c = raw[i]
        if c == "\n" {
            let hi = i
            if i > 0 && raw[i - 1] == "\r" { hi = i - 1 }
            if hi > lo {
                if first == "0" { out = sbAppend(out, ",") }
                out = sbAppend(out, substring(raw, lo, hi))
                first = "0"
            }
            lo = i + 1
        }
        i += 1
    }
    if lo < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, substring(raw, lo, n))
    }
    emit sbToString(out)
}

// os.mkdir(p)
func osmkdirk(p) {
    exec("mkdir \"" + p + "\"")
    emit ""
}

// os.remove(p) -- file remove only (use os.rmdir for dirs).
func osremovek(p) {
    exec("del \"" + p + "\"")
    emit ""
}

// os.rmdir(p) -- empty directory remove.
func osrmdirk(p) {
    exec("rmdir \"" + p + "\"")
    emit ""
}

// os.rename(src, dst)
func osrenamek(src, dst) {
    exec("ren \"" + src + "\" \"" + dst + "\"")
    emit ""
}

// os.system(cmd) -- run via shell, return exit code (best-effort).
// Today: exec() captures stdout but the exit code surfaces via
// shellRun if available; degrade to "0" on success.
func ossystemk(cmd) {
    exec(cmd)
    emit "0"
}


// SECURITY NOTE
// -------------
// Several functions above shell out with `exec(<concatenated string>)`.
// Caller-supplied paths are NOT sanitized; programs that accept
// untrusted input must escape before passing to these functions.  See
// the Tier-A roadmap item for the planned `winRun`
// CreateProcess-based replacement that kills the shell-quoting tax.
