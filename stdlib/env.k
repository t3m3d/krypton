// stdlib/env.k — environment variables for KryptScript. PURE KRYPTON, no clang.
//
// The native getenv builtin doesn't work on the C-free backend, so this reads
// the environment through `exec` (printenv) instead. macOS + Linux.
//
//   env("HOME")              -> "/Users/brian"
//   env("MISSING")           -> ""
//   envOr("PORT", "8080")    -> value or the default
//   envBool("DEBUG")         -> "1" if set to 1/true/yes/on, else "0"
//   hasEnv("PATH")           -> "1" / "0"
//
// Note: reads the *inherited* environment. Setting a var from a script only
// affects child processes you spawn with exec in the same command string.

module env

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

func _q(s) { emit "\"" + s + "\"" }

// env(name): the value of an environment variable, or "" if unset.
func env(name) { emit _chomp(exec("printenv " + _q(name) + " 2>/dev/null")) }

// hasEnv(name): "1" if the variable is set (even to empty), else "0".
func hasEnv(name) {
    emit _chomp(exec("( printenv " + _q(name) + " >/dev/null 2>&1 ) && echo 1 || echo 0"))
}

// envOr(name, dflt): the value, or dflt when unset/empty.
func envOr(name, dflt) {
    let v = env(name)
    if v == "" { emit dflt }
    emit v
}

// envInt(name, dflt): value parsed as int (dflt is an int), or dflt if unset.
func envInt(name, dflt) {
    let v = env(name)
    if v == "" { emit dflt }
    emit toInt(v)
}

// envBool(name): "1" for 1/true/yes/on (case-insensitive), else "0".
func envBool(name) {
    let v = _chomp(exec("printenv " + _q(name) + " 2>/dev/null | tr 'A-Z' 'a-z'"))
    if v == "1" { emit "1" }
    if v == "true" { emit "1" }
    if v == "yes" { emit "1" }
    if v == "on" { emit "1" }
    emit "0"
}

// path(): the PATH variable. pathDirs(): its entries, one per line.
func path() { emit env("PATH") }
func pathDirs() { emit exec("printf '%s' \"$PATH\" | tr ':' '\\n'") }
