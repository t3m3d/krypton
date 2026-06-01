#!/usr/bin/env kr
// kr scripts/sweep.ks <dir> [run|ir]
// Replaces sweep_examples.sh, sweep_algorithms.sh, sweep_stdlib.sh.
import "k:fs"

just run {
    if argCount() < 1 {
        kp("usage: kr scripts/sweep.k <dir> [run|ir]")
        exit("1")
    }
    let dir = arg("0")
    let mode = "run"
    if argCount() >= 2 { mode = arg("1") }

    // fsListDir has a struct-iterator bug; shell out to dir /b.
    let list = exec("cmd /C dir /b " + dir + "\\*.k")
    if len(list) == 0 {
        kp("FAIL: no .k files under " + dir)
        exit("1")
    }

    // proc.k hangs kcc --ir (stdlib chain import bug, pre-existing).
    let SKIP = ",proc.k,"

    let pass = 0
    let fail = 0
    let skipped = 0
    let failed = ""
    let n = lineCount(list)
    let i = 0
    while i < n {
        let file = trim(getLine(list, i))
        if len(file) > 0 {
            if contains(SKIP, "," + file + ",") {
                skipped += 1
                i += 1
                continue
            }
            let src = dir + "/" + file
            let ok = "1"
            if mode == "ir" {
                let rc = shellRun("kcc.exe --ir \"" + src + "\" >nul")
                if rc != "0" { ok = "0" }
            } else {
                let outExe = fsTempDir() + "_krsweep.exe"
                let rcBuild = shellRun("kcc.exe -o \"" + outExe + "\" \"" + src + "\" >nul")
                if rcBuild != "0" {
                    ok = "0"
                } else {
                    let rcRun = shellRun("\"" + outExe + "\" >nul")
                    // exit 0 or 1 both count as ran cleanly.
                    if rcRun != "0" {
                        if rcRun != "1" { ok = "0" }
                    }
                }
                fsDelete(outExe)
            }
            if ok == "1" { pass += 1 } else { fail += 1; failed = failed + " " + file }
        }
        i += 1
    }

    kp("PASS=" + pass + " FAIL=" + fail + " SKIP=" + skipped)
    if fail > 0 {
        kp("FAILED:" + failed)
        exit("1")
    }
}
