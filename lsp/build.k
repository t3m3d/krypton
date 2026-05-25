#!/usr/bin/env kr
// kr lsp/build.k — build kls.exe from lsp/kls.k.
//
// CURRENTLY USES C+gcc — this is the deprecated path. Migrate to
// `kcc.exe -o kls.exe lsp/kls.k` (native pipeline) as soon as kls.k
// builds cleanly that way. Same goal as kcc.sh's --gcc deprecation:
// no C compiler in the user-invocation path, ever.
import "k:fs"

just run {
    let root = fsCwd()

    kp("[1/2] kcc.exe lsp/kls.k -> lsp/_kls.c")
    let rcKcc = shellRun("kcc.exe lsp\\kls.k > lsp\\_kls.c")
    if rcKcc != "0" {
        kp("kcc failed (rc=" + rcKcc + ")")
        exit("1")
    }

    // DEPRECATED step — when kls.k builds via native, drop steps 1+2
    // and replace with a single `kcc.exe -o kls.exe lsp/kls.k`.
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
