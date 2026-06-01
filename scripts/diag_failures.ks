#!/usr/bin/env kr
// kr scripts/diag_failures.ks
// Replaces diag_failures.sh. Classify each known-failing example:
// IR-fail / build-fail / runtime-fail.
import "k:fs"

let FAILED = "binary_convert,calculator,debug_pair,import_demo,number_format,run_committed,runtokcount,string_compress,test_tokenize"

// Hang kcc.exe -o without returning; skip until shellRun has a timeout primitive.
let HANG = ",calculator,import_demo,run_committed,"

just run {
    let n = length(FAILED)
    let i = 0
    while i < n {
        let name = split(FAILED, i + "")
        let f = "examples/" + name + ".k"
        if fsFileExists(f) != "1" {
            kp(name + ": missing")
        } else if contains(HANG, "," + name + ",") {
            kp(name + ": SKIP (hangs kcc.exe -o; needs shellRun timeout)")
        } else {
            let irPath = fsTempDir() + "_krdiag_ir.txt"
            shellRun("kcc.exe --ir \"" + f + "\" >" + irPath + " 2>nul")
            let irText = readFile(irPath)
            let irSz = len(irText)
            fsDelete(irPath)

            if irSz == 0 {
                kp(name + ": IR=0 (compile.k silent failure)")
            } else {
                let outExe = fsTempDir() + "_krdiag.exe"
                let rcBuild = shellRun("kcc.exe -o \"" + outExe + "\" \"" + f + "\" >nul")
                if rcBuild != "0" {
                    kp(name + ": IR=" + irSz + ", native compile failed RC=" + rcBuild)
                } else if fsFileExists(outExe) != "1" {
                    kp(name + ": IR=" + irSz + ", no binary produced")
                } else {
                    let rcRun = shellRun("\"" + outExe + "\" >nul")
                    kp(name + ": IR=" + irSz + ", runtime RC=" + rcRun)
                }
                fsDelete(outExe)
            }
        }
        i += 1
    }
}
