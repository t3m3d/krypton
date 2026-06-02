#!/usr/bin/env kr
// dirstat.ks — KryptScript demo: directory stats, 100% C-free on macOS/Linux.
//
//   kr examples/ks/dirstat.ks [DIR]
//   ./examples/ks/dirstat.ks .          (after chmod +x)
//
// Shows off the C-free scripting stdlib built on the native `exec` builtin:
//   k:args  k:fsx  k:env  k:sh  k:ansi
// No clang, no k:fs (Windows C), no broken getenv — just syscalls.

import "k:args"
import "k:fsx"
import "k:env"
import "k:sh"
import "k:ansi"

just run {
    // arg(0) is the first user arg; default to "." if none given.
    let dir = "."
    if argCount() >= 1 { dir = arg(0) }

    if exists(dir) == "0" {
        kp(red("no such path: ") + dir)
        exit("1")
    }

    kp(bold(cyan("dirstat")) + "  " + dir)
    kp(gray("host: " + sh("uname -srm") + "   user: " + env("USER")))
    kp("")

    // Count files vs dirs using the C-free listings.
    let files = listFiles(dir)
    let dirs  = listDirs(dir)
    let nFiles = lineCount(files)
    let nDirs  = lineCount(dirs)
    // lineCount counts a trailing-newline-terminated empty tail as a line;
    // guard the empty case.
    if len(files) == 0 { nFiles = 0 }
    if len(dirs) == 0  { nDirs = 0 }

    kp(green("files: ") + toStr(nFiles) + "    " + yellow("dirs: ") + toStr(nDirs))

    // Total bytes of the regular files (sum via the size() helper).
    let total = 0
    let i = 0
    while i < nFiles {
        let f = getLine(files, i)
        if len(f) > 0 { total = total + size(f) }
        i += 1
    }
    kp(green("bytes: ") + toStr(total))

    // Biggest file, via a shell one-liner (du+sort) — still C-free, just exec.
    let big = sh("ls -1S " + q(dir) + " 2>/dev/null | head -1")
    if big != "" { kp(green("largest: ") + big) }
}
