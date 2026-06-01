#!/usr/bin/env kr
// kr scripts/check_headers.k
// Replaces check_headers.sh. Smoke-tests every headers/*.krh by
// importing it into a one-liner and checking kcc accepts the IR.
import "k:fs"

func _smokeSource(headerName) {
    emit "import \"head:" + headerName + "\"\n\njust run { kp(\"ok\") }\n"
}

just run {
    let tmpDir = fsTempDir() + "krhdr_smoke"
    fsMkdir(tmpDir)

    let list = exec("cmd /C dir /b headers\\*.krh")
    if len(list) == 0 {
        kp("FAIL: no headers/")
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
            let base = file
            if endsWith(base, ".krh") { base = substring(base, 0, len(base) - 4) }

            let srcPath = tmpDir + "/" + base + "_smoke.k"
            writeFile(srcPath, _smokeSource(base))

            let cmd = "kcc.exe --ir \"" + srcPath + "\" >nul"
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
