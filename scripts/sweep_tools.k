#!/usr/bin/env kr
// kr scripts/sweep_tools.k
// Replaces sweep_tools.sh.
import "k:fs"

let ARG_DEFAULT = "examples/hello.k"

func _argsFor(name) {
    if name == "mkelf_hello.k" { emit "" }
    if name == "diff_lines.k"  { emit ARG_DEFAULT + " " + ARG_DEFAULT }
    if name == "head.k"        { emit "3 " + ARG_DEFAULT }
    if name == "tail.k"        { emit "3 " + ARG_DEFAULT }
    if name == "fold.k"        { emit "40 " + ARG_DEFAULT }
    // need richer args; smoke only.
    if name == "cut.k"         { emit "" }
    if name == "fmt.k"         { emit "" }
    if name == "grep.k"        { emit "" }
    if name == "indent.k"      { emit "" }
    if name == "replace.k"     { emit "" }
    emit ARG_DEFAULT
}

just run {
    let list = exec("cmd /C dir /b tools\\*.k")
    if len(list) == 0 {
        kp("FAIL: no tools/")
        exit("1")
    }
    let pass = 0
    let fail = 0
    let failed = ""
    let n = lineCount(list)
    let i = 0
    while i < n {
        let file = trim(getLine(list, i))
        if len(file) > 0 {
            let src = "tools/" + file
            let outExe = fsTempDir() + "_krsweep_tool.exe"
            let rcBuild = shellRun("kcc.exe -o \"" + outExe + "\" \"" + src + "\" > nul")
            let ok = "1"
            if rcBuild != "0" {
                ok = "0"
                failed = failed + " " + file + "(build)"
            } else {
                let args = _argsFor(file)
                let rcRun = "0"
                if len(args) > 0 {
                    rcRun = shellRun("\"" + outExe + "\" " + args + " > nul")
                }
                // exit 0/1/2 all count as ran (CLI conventions for no-input / no-match / usage).
                if rcRun != "0" {
                    if rcRun != "1" {
                        if rcRun != "2" {
                            ok = "0"
                            failed = failed + " " + file + "(" + rcRun + ")"
                        }
                    }
                }
            }
            if ok == "1" { pass += 1 } else { fail += 1 }
            fsDelete(outExe)
        }
        i += 1
    }
    kp("PASS=" + pass + " FAIL=" + fail)
    if fail > 0 {
        kp("FAILED:" + failed)
        exit("1")
    }
}
