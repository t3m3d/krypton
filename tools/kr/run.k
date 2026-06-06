// tools/kr/run.k — kr.exe entry point.
//
// Native Windows "run-this-Krypton-script" wrapper. Same role as the
// POSIX `kr` bash script except built as a real PE so cmd.exe /
// PowerShell / Explorer double-click all reach it without bash or WSL.
//
//   kr                      → interactive REPL (accumulating)
//   kr script.ks [args...]  → run script; args forwarded; exit code mirrored
//
// SWIFT-LIKE TOP-LEVEL CODE: if a script has no `just run { }` block, kr
// auto-wraps its whole body in one — write statements at the top of the
// file with no boilerplate. `import` and `func` work inside the wrap too.
// Scripts that already contain `just run` (or declare a `module`) run as-is.
//
// Installer wiring: `.ks` registers under HKCR ProgID `KryptonScript.Run`
// whose open-command is `"C:\krypton\kr.exe" "%1" %*`.

just run {
    if argCount() == 0 {
        _repl()
        exit(0)
    }

    let script = arg("0")

    // Try to read the file so we can decide whether to wrap. If we can't
    // (missing file, permission, etc.), fall through to a direct pass —
    // kcc itself will produce the right error.
    let body = ""
    body = readFile(script)

    let wrapTmp = ""
    let finalScript = script
    if len(body) > 0 {
        if _needsWrap(body) == "1" {
            wrapTmp = _tempScriptPath()
            let payload = sbNew()
            payload = sbAppend(payload, "just run {\n")
            payload = sbAppend(payload, _stripShebang(body))
            payload = sbAppend(payload, "\n}\n")
            writeFile(wrapTmp, sbToString(payload))
            finalScript = wrapTmp
        }
    }

    let tmpExe = _tempExePath()
    let buildCmd = _cmdWrap("kcc -o " + _quote(tmpExe) + " " + _quote(finalScript))
    let buildRc = shellRun(buildCmd)
    if toInt(buildRc) != 0 {
        DeleteFileA(tmpExe)
        if wrapTmp != "" { DeleteFileA(wrapTmp) }
        exit(toInt(buildRc))
    }

    let runInner = _quote(tmpExe)
    let i = 1
    while i < argCount() {
        runInner = runInner + " " + _quote(arg("" + i))
        i = i + 1
    }
    let runRc = shellRun(_cmdWrap(runInner))

    DeleteFileA(tmpExe)
    if wrapTmp != "" { DeleteFileA(wrapTmp) }
    exit(toInt(runRc))
}

// ─── auto-wrap helpers ────────────────────────────────────────────────

// True (returns "1") iff the source has neither an explicit `just run`
// entry point nor a top-level `module` declaration. We strip // line
// comments first so the words inside a comment don't fool the detector.
func _needsWrap(src) {
    let stripped = _stripLineComments(src)
    if _hasJustRun(stripped) == "1" { emit "0" }
    if _hasModuleDecl(stripped) == "1" { emit "0" }
    emit "1"
}

// Walk char by char, drop everything from `//` to end-of-line.
// Doesn't honour string literals — neither does the POSIX kr's sed.
func _stripLineComments(s) {
    let n = len(s)
    let i = 0
    let out = sbNew()
    while i < n {
        let c = s[i]
        if c == "/" {
            let isComment = "0"
            if i + 1 < n {
                if s[i + 1] == "/" { isComment = "1" }
            }
            if isComment == "1" {
                while i < n {
                    if s[i] == "\n" {
                        out = sbAppend(out, "\n")
                        i = i + 1
                        break
                    }
                    i = i + 1
                }
            } else {
                out = sbAppend(out, c)
                i = i + 1
            }
        } else {
            out = sbAppend(out, c)
            i = i + 1
        }
    }
    emit sbToString(out)
}

// True iff `just` followed by whitespace and `run` appears with non-word
// boundaries on both sides. Mirrors the bash:
//   grep -qE '(^|[^[:alnum:]_])just[[:space:]]+run([^[:alnum:]_]|$)'
func _hasJustRun(s) {
    let n = len(s)
    let i = 0
    while i + 8 <= n {
        if s[i] == "j" {
            if _isWordBoundaryBefore(s, i) == "1" {
                if s[i + 1] == "u" {
                    if s[i + 2] == "s" {
                        if s[i + 3] == "t" {
                            if _isSpace(s[i + 4]) == "1" {
                                let j = i + 4
                                while j < n {
                                    if _isSpace(s[j]) == "1" { j = j + 1 } else { break }
                                }
                                if j + 3 <= n {
                                    if s[j] == "r" {
                                        if s[j + 1] == "u" {
                                            if s[j + 2] == "n" {
                                                let k = j + 3
                                                if k >= n {
                                                    emit "1"
                                                }
                                                if k < n {
                                                    if _isWordChar(s[k]) == "0" { emit "1" }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        i = i + 1
    }
    emit "0"
}

// True iff any line begins (after leading spaces/tabs) with `module ` or
// `module\t`. Mirrors `^[[:space:]]*module[[:space:]]`.
func _hasModuleDecl(s) {
    let n = len(s)
    let i = 0
    let atLineStart = "1"
    while i < n {
        if atLineStart == "1" {
            while i < n {
                if s[i] == " " || s[i] == "\t" { i = i + 1 } else { break }
            }
            if i + 7 <= n {
                if s[i] == "m" {
                    if s[i + 1] == "o" {
                        if s[i + 2] == "d" {
                            if s[i + 3] == "u" {
                                if s[i + 4] == "l" {
                                    if s[i + 5] == "e" {
                                        if _isSpace(s[i + 6]) == "1" { emit "1" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            atLineStart = "0"
        }
        if i < n {
            if s[i] == "\n" { atLineStart = "1" }
            i = i + 1
        }
    }
    emit "0"
}

func _stripShebang(s) {
    if len(s) < 2 { emit s }
    if s[0] != "#" { emit s }
    if s[1] != "!" { emit s }
    let n = len(s)
    let i = 0
    while i < n {
        if s[i] == "\n" { i = i + 1  break }
        i = i + 1
    }
    let out = sbNew()
    while i < n {
        out = sbAppend(out, s[i])
        i = i + 1
    }
    emit sbToString(out)
}

func _isSpace(c) {
    if c == " " { emit "1" }
    if c == "\t" { emit "1" }
    emit "0"
}

func _isWordChar(c) {
    if c == "_" { emit "1" }
    if c >= "0" { if c <= "9" { emit "1" } }
    if c >= "A" { if c <= "Z" { emit "1" } }
    if c >= "a" { if c <= "z" { emit "1" } }
    emit "0"
}

func _isWordBoundaryBefore(s, i) {
    if i == 0 { emit "1" }
    if _isWordChar(s[i - 1]) == "0" { emit "1" }
    emit "0"
}

// ─── REPL ─────────────────────────────────────────────────────────────
//
// Krypton has no interpreter, so this is an accumulating REPL: lines
// starting with `import`/`func`/`struct`/`let` are remembered and
// re-emitted around each new line, which is compiled + run fresh.
// Bare expressions/statements run once (type `kp(expr)` to see a value).

func _repl() {
    kp("KryptScript REPL — Krypton 2.3.0  (:help, :q to quit)")
    let imports = sbNew()
    let defs = sbNew()
    // readLine returns "" both for "user hit Enter" and "stdin closed".
    // Krypton has no separate EOF signal yet, so treat 3 consecutive
    // empties as EOF — natural for piped scripts, harmless for humans
    // (they'd type :q anyway).
    let emptyStreak = 0
    while "1" == "1" {
        let line = readLine("ks> ")
        if len(line) == 0 {
            emptyStreak = emptyStreak + 1
            if emptyStreak >= 3 { break }
            continue
        }
        emptyStreak = 0
        if line == ":q"     { break }
        if line == ":quit"  { break }
        if line == ":exit"  { break }
        if line == ":help"  { _replHelp() continue }
        if line == ":reset" { imports = sbNew()  defs = sbNew()  kp("(state cleared)") continue }
        if line == ":list"  { _replList(imports, defs) continue }

        // Multi-line continuation until braces balance.
        let depth = _braceDelta(line)
        while depth > 0 {
            let more = readLine("..> ")
            let mb = sbNew()
            mb = sbAppend(mb, line)
            mb = sbAppend(mb, "\n")
            mb = sbAppend(mb, more)
            line = sbToString(mb)
            depth = depth + _braceDelta(more)
        }

        let tmp = _tempReplPath()
        let prog = sbNew()
        if len(sbToString(imports)) > 0 {
            prog = sbAppend(prog, sbToString(imports))
            prog = sbAppend(prog, "\n")
        }
        prog = sbAppend(prog, "just run {\n")
        if len(sbToString(defs)) > 0 {
            prog = sbAppend(prog, sbToString(defs))
            prog = sbAppend(prog, "\n")
        }
        prog = sbAppend(prog, line)
        prog = sbAppend(prog, "\n}\n")
        writeFile(tmp, sbToString(prog))

        let tmpExe = _tempExePath()
        let buildRc = shellRun(_cmdWrap("kcc -o " + _quote(tmpExe) + " " + _quote(tmp)))
        if toInt(buildRc) == 0 {
            shellRun(_cmdWrap(_quote(tmpExe)))
            // Remember definitions/bindings so later lines can use them.
            if _startsWith(line, "import ") == "1" {
                if len(sbToString(imports)) > 0 { imports = sbAppend(imports, "\n") }
                imports = sbAppend(imports, line)
            }
            if _startsWith(line, "func ") == "1" {
                if len(sbToString(defs)) > 0 { defs = sbAppend(defs, "\n") }
                defs = sbAppend(defs, line)
            }
            if _startsWith(line, "struct ") == "1" {
                if len(sbToString(defs)) > 0 { defs = sbAppend(defs, "\n") }
                defs = sbAppend(defs, line)
            }
            if _startsWith(line, "let ") == "1" {
                if len(sbToString(defs)) > 0 { defs = sbAppend(defs, "\n") }
                defs = sbAppend(defs, line)
            }
        }
        DeleteFileA(tmpExe)
        DeleteFileA(tmp)
    }
    kp("bye")
}

func _replHelp() {
    kp("  Krypton expressions/statements run immediately.")
    kp("  import/func/struct/let are remembered for later lines.")
    kp("  :list   show remembered defs    :reset  clear them")
    kp("  :q      quit                    (Ctrl-Z+Enter also quits)")
}

func _replList(imports, defs) {
    let i = sbToString(imports)
    let d = sbToString(defs)
    if len(i) > 0 { kp(i) }
    if len(d) > 0 { kp(d) }
    if len(i) == 0 {
        if len(d) == 0 { kp("(nothing remembered yet)") }
    }
}

func _braceDelta(s) {
    let n = len(s)
    let i = 0
    let d = 0
    while i < n {
        if s[i] == "{" { d = d + 1 }
        if s[i] == "}" { d = d - 1 }
        i = i + 1
    }
    emit d
}

func _startsWith(s, prefix) {
    let pn = len(prefix)
    if len(s) < pn { emit "0" }
    let i = 0
    while i < pn {
        if s[i] != prefix[i] { emit "0" }
        i = i + 1
    }
    emit "1"
}

// ─── temp path + quote helpers ────────────────────────────────────────

func _cmdWrap(s) { emit "\"" + s + "\"" }

func _tempExePath() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    let dir = ""
    if n != "0" { dir = bufStr(buf) }
    if len(dir) == 0 { dir = "C:\\Windows\\Temp\\" }
    let id = GetTickCount()
    emit dir + "_kr_" + id + ".exe"
}

func _tempScriptPath() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    let dir = ""
    if n != "0" { dir = bufStr(buf) }
    if len(dir) == 0 { dir = "C:\\Windows\\Temp\\" }
    let id = GetTickCount()
    emit dir + "_kr_wrap_" + id + ".ks"
}

func _tempReplPath() {
    let buf = bufNew(1024)
    let n = GetTempPathA("1024", buf)
    let dir = ""
    if n != "0" { dir = bufStr(buf) }
    if len(dir) == 0 { dir = "C:\\Windows\\Temp\\" }
    let id = GetTickCount()
    emit dir + "_kr_repl_" + id + ".ks"
}

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
