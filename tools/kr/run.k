// tools/kr/run.k — kr.exe entry point.
//
// Native Windows "run-this-Krypton-script" wrapper. Same role as the
// POSIX `kr` bash script (a thin `kcc.sh -r` shim), except built as a
// real PE so cmd.exe / PowerShell / Explorer double-click all reach it
// without bash or WSL.
//
// kcc.exe itself doesn't ship -r mode — that lives only in `kcc.sh`.
// kr.exe owns the equivalent flow:
//
//   1. Read its own command line. arg(0) = script path, arg(1..) = args
//      forwarded to the script.
//   2. Compile the script to a uniquely-named temp .exe in %TEMP% with
//      `kcc -o <tmp> <script>`. Stderr from kcc surfaces to the user.
//   3. Run the temp .exe with the script args. Stdio is inherited (kcc's
//      `kr_shellrun` synchronously forwards stdin/stdout/stderr).
//   4. Delete the temp .exe and exit with the script's real exit code so
//      `%ERRORLEVEL%` / `$LastExitCode` reflects what the script returned.
//
// Installer wiring: `.ks` registers under HKCR ProgID `KryptonScript.Run`
// whose open-command is `"C:\krypton\kr.exe" "%1" %*`. Double-click and
// `myscript.ks foo bar` from any shell both land here.

just run {
    if argCount() < 1 {
        printErr("kr: usage: kr <script.k|script.ks> [args...]\n")
        printErr("  Compiles and runs a Krypton script, forwarding args to it.\n")
        printErr("  Returns the script's exit code.\n")
        exit(1)
    }

    let script = arg("0")
    let tmpExe = _tempExePath()

    // Compile. _cmdWrap dual-quotes the whole command so cmd.exe's quote
    // stripping leaves the inner quotes intact (CMD strips its outermost
    // pair when it sees ^".*^"$, which would mangle interior quoted args).
    let buildCmd = _cmdWrap("kcc -o " + _quote(tmpExe) + " " + _quote(script))
    let buildRc = shellRun(buildCmd)
    if toInt(buildRc) != 0 {
        DeleteFileA(tmpExe)
        exit(toInt(buildRc))
    }

    // Run the compiled binary with the user's args.
    let runInner = _quote(tmpExe)
    let i = 1
    while i < argCount() {
        runInner = runInner + " " + _quote(arg("" + i))
        i = i + 1
    }
    let runRc = shellRun(_cmdWrap(runInner))

    DeleteFileA(tmpExe)
    exit(toInt(runRc))
}

// CMD.EXE quote rule: if a command starts and ends with `"`, cmd strips
// exactly one outer pair before parsing. So when we pass a command that
// already contains its own quoted args, we wrap the WHOLE thing in an
// extra `"..."` so the inner quotes survive cmd's strip pass.
func _cmdWrap(s) { emit "\"" + s + "\"" }

// Build a per-invocation temp .exe path under %TEMP%, e.g.
// "C:\Users\me\AppData\Local\Temp\_kr_4271983.exe". GetTickCount gives
// us a millisecond resolution counter — collisions across concurrent
// kr.exe invocations are improbable enough for a transient .exe.
func _tempExePath() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    let dir = ""
    if n != "0" { dir = bufStr(buf) }
    if len(dir) == 0 { dir = "C:\\Windows\\Temp\\" }
    let id = GetTickCount()
    emit dir + "_kr_" + id + ".exe"
}

// Quote one token for CMD.EXE / Windows argv parsing. We only add
// quotes when they're NEEDED (arg contains a space, tab, or `"`),
// because Krypton's own GetCommandLineA parser today preserves quote
// chars literally rather than stripping the surrounding pair like the
// MSVC CRT does. So `kr foo.ks fail` would otherwise reach the script
// as `arg(0) = "\"fail\""` and break a normal `arg(0) == "fail"` check.
//
// When quoting IS required (path with spaces, arg with embedded `"`),
// we still wrap; the rough edges on the receiving side are preferable
// to losing whitespace altogether.
func _quote(s) {
    if len(s) == 0 { emit "\"\"" }
    let needs = 0
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == " " || c == "\t" || c == "\"" { needs = 1 }
        i = i + 1
    }
    if needs == 0 { emit s }
    let out = "\""
    i = 0
    while i < len(s) {
        let c = s[i]
        if c == "\"" {
            out = out + "\\\""
        } else {
            out = out + c
        }
        i = i + 1
    }
    emit out + "\""
}
