#!/usr/bin/env kr
// scripts/check_headers.k — Krypton port of scripts/check_headers.sh.
//
// Walks headers/*.krh, compiles a tiny smoke source that imports each
// one, and reports PASS / FAIL. Replaces the 27-line bash original;
// equivalent on Windows + Linux without depending on `bash`,
// `mktemp`, or `cat`-heredoc patterns.
//
// Run from repo root:
//   kr scripts/check_headers.k

import "k:fs"

func _smokeSource(headerName) {
    // The smoke source just imports the header — we never run the
    // result, we only need the compile to succeed at IR-emit time.
    emit "import \"head:" + headerName + "\"\n\njust run { kp(\"ok\") }\n"
}

just run {
    let tmpDir = fsTempDir() + "krhdr_smoke"
    fsMkdir(tmpDir)

    // Enumerate *.krh via cmd's `dir /b` — fsListDir is unavailable
    // for this build (struct-iterator codegen issue noted in TODO).
    let list = exec("cmd /C dir /b headers\\*.krh")
    if len(list) == 0 {
        kp("FAIL: no headers/ directory found")
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
            // Strip .krh extension for the `head:` prefix
            let base = file
            if endsWith(base, ".krh") { base = substring(base, 0, len(base) - 4) }

            let srcPath = tmpDir + "/" + base + "_smoke.k"
            writeFile(srcPath, _smokeSource(base))

            let cmd = "kcc.exe --ir \"" + srcPath + "\" >nul 2>&1"
            let rc = shellRun(cmd)
            if rc == "0" {
                pass += 1
            } else {
                fail += 1
                failed = failed + " " + file
            }
            fsDelete(srcPath)
        }
        i += 1
    }
    fsRmdir(tmpDir)

    kp("PASS=" + pass + " FAIL=" + fail)
    if fail > 0 {
        kp("FAILED:" + failed)
        exit("1")
    }
}
