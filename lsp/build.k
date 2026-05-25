#!/usr/bin/env kr
// kr lsp/build.k
// Replaces lsp/build.bat. Compiles lsp/kls.k → kls.exe via kcc + gcc.
import "k:fs"

just run {
    let root = fsCwd()

    kp("[1/2] kcc.exe lsp/kls.k -> lsp/_kls.c")
    let rcKcc = shellRun("kcc.exe lsp\\kls.k > lsp\\_kls.c")
    if rcKcc != "0" {
        kp("kcc failed (rc=" + rcKcc + ")")
        exit("1")
    }

    kp("[2/2] gcc lsp/_kls.c -> kls.exe")
    let rcGcc = shellRun("gcc lsp\\_kls.c -o kls.exe -w")
    if rcGcc != "0" {
        kp("gcc failed (rc=" + rcGcc + ")")
        exit("1")
    }

    kp("")
    kp("built kls.exe")
    if fsFileExists("kls.exe") == "1" {
        kp("kls.exe present in " + root)
    } else {
        kp("WARN: kls.exe not found after build")
    }
}
