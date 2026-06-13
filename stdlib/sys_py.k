// stdlib/sys_py.k -- Python `sys` module surface on existing Krypton
// builtins.  Named with the `*k` suffix convention (matches builtins.k
// + string_py.k + list_py.k + dict_py.k).
//
// FE lowering:
//   sys.argv             -> sysargvk()
//   sys.argv[i]          -> arg(strk(i))    (Krypton builtin)
//   sys.exit(code)       -> sysexitk(code)
//   sys.stdout.write(s)  -> sysstdoutwritek(s)
//   sys.stderr.write(s)  -> sysstderrwritek(s)
//   sys.platform         -> sysplatformk()
//   sys.version          -> sysversionk()

module sys_py


// sys.argv -- newline-joined string of all argv entries (program name
// at index 0 is omitted in Krypton's `arg()` convention, matching
// Python's sys.argv[1:] effectively).  Caller uses split(args, i) to
// index.
func sysargvk() {
    let n = argCount()
    let out = sbNew()
    let i = 0
    let first = "1"
    while i < n {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, arg(strFromInt(i)))
        first = "0"
        i += 1
    }
    emit sbToString(out)
}

// sys.argc -- not in Python, but useful Krypton-native alias.
func sysargck() {
    emit argCount()
}

// sys.exit(code) -- alias.
func sysexitk(code) {
    exit(code)
}

// sys.stdout.write(s) -- print without trailing newline.
// Krypton's `print` adds \n; emulate the no-newline write with two
// half-prints around a manual concat, or just use writeBytes to stdout.
// Simplest: collect into a buffer; flush at end.  For correctness
// today, append a no-op and let print add newline (matches Python's
// print() default behavior more than .write() semantics).  Future: a
// real `writeStdout(s)` Krypton builtin would let us drop the \n.
func sysstdoutwritek(s) {
    print(s)
}

func sysstderrwritek(s) {
    printErr(s)
}

// sys.platform -- the Krypton platform tag.  Returns "win32" /
// "darwin" / "linux" so cross-platform Krypton code matches the
// strings Python users expect.
func sysplatformk() {
    // No native platform-detect builtin yet; conservatively report
    // "win32" since this file ships on every backend (a backend-
    // specific override can be added in the BE-private stdlib).
    emit "win32"
}

// sys.version -- a static Krypton version string.  Real injection
// from the build is a TODO.
func sysversionk() {
    emit "2.4.x (krypton)"
}

// sys.maxsize -- the largest int Krypton smart-ints can hold safely
// without crossing the pointer-classification boundary (2^31 - 1
// on x86, 2^63 - 1 on aarch64).  Use the conservative x86 number.
func sysmaxsizek() {
    emit 2147483647
}


// Helper: stringify an int (Krypton uses strk in builtins.k; aliased
// here so we don't pull in the whole builtins module for one call).
func strFromInt(n) {
    emit "" + n
}
