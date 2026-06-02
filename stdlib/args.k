// stdlib/args.k — command-line argument parsing in PURE KRYPTON. No C.
//
// Built on the native arg(i) / argCount() builtins. arg(0) is the FIRST user
// argument (the program name is not included), argCount() is how many there are.
//
//   kc myprog --name brian -v file.txt
//   -> argCount()==4, arg(0)=="--name", arg(1)=="brian", ...
//
// State is threaded explicitly (no module globals across the import boundary):
// each accessor re-scans arg()/argCount(), so just call them directly.
//
//   hasFlag("-v")            -> "1" if any arg equals "-v" or "--v"
//   optValue("--name", "?")  -> value after "--name", else the default
//   positional(0)            -> first arg that isn't a flag / flag-value
//   restFrom(1)              -> args joined from index 1 onward

module args

func _at(i) { emit arg(i) }
func argN()  { emit argCount() }

// hasFlag(name): "1" if `name` appears as a standalone argument, else "0".
// Matches the exact token (pass it with its dashes, e.g. "-v" or "--verbose").
func hasFlag(name) {
    let i = 0
    let n = argCount()
    while i < n {
        if arg(i) == name { emit "1" }
        i += 1
    }
    emit "0"
}

// optValue(name, dflt): the token following `name` ("--name brian" -> "brian").
// Also accepts "--name=brian" form. Returns dflt if not present.
func optValue(name, dflt) {
    let i = 0
    let n = argCount()
    let pfx = name + "="
    while i < n {
        let a = arg(i)
        if a == name {
            if i + 1 < n { emit arg(i + 1) }
            emit dflt
        }
        if startsWith(a, pfx) {
            emit substring(a, len(pfx), len(a))
        }
        i += 1
    }
    emit dflt
}

func _isFlag(a) {
    if startsWith(a, "-") { emit 1 }
    emit 0
}

// positional(k): the k-th argument that is NOT a flag and NOT a flag's value.
// Returns "" if there aren't that many. Flag values are skipped (the token
// right after a "--x" style flag, unless that flag uses "=" form).
func positional(k) {
    let i = 0
    let n = argCount()
    let found = 0
    while i < n {
        let a = arg(i)
        if _isFlag(a) == 1 {
            // "--x=v" carries its value; "--x v" consumes the next token
            if indexOf(a, "=") < 0 {
                if i + 1 < n {
                    if _isFlag(arg(i + 1)) == 0 { i += 1 }
                }
            }
        } else {
            if found == k { emit a }
            found += 1
        }
        i += 1
    }
    emit ""
}

// countPositional(): how many positional (non-flag) arguments exist.
func countPositional() {
    let i = 0
    let n = argCount()
    let cnt = 0
    while i < n {
        let a = arg(i)
        if _isFlag(a) == 1 {
            if indexOf(a, "=") < 0 {
                if i + 1 < n {
                    if _isFlag(arg(i + 1)) == 0 { i += 1 }
                }
            }
        } else {
            cnt += 1
        }
        i += 1
    }
    emit cnt
}

// restFrom(start): all args from index `start` joined with single spaces.
func restFrom(start) {
    let sb = sbNew()
    let i = start
    let n = argCount()
    while i < n {
        if i > start { sb = sbAppend(sb, " ") }
        sb = sbAppend(sb, arg(i))
        i += 1
    }
    emit sbToString(sb)
}

// allArgs(): every argument joined with spaces (the full command tail).
func allArgs() { emit restFrom(0) }
