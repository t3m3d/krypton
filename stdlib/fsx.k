// stdlib/fsx.k — C-free filesystem for KryptScript on macOS/Linux. No clang.
//
// The existing k:fs uses Windows FindFirstFileA via cfunc (needs a C compiler).
// k:fsx does the same jobs through the native `exec` builtin (POSIX coreutils),
// so it works on the clang-free native path. macOS + Linux.
//
//   exists("/etc/hosts")     -> "1" / "0"
//   isDir("/tmp")            -> "1" / "0"
//   listDir("/tmp")          -> "a\nb\nc\n"  (iterate via lineCount/getLine)
//   mkdirp("a/b/c")          -> makes the whole path
//   readText / writeText / appendText
//
// File read/write use the native readFile/writeFile builtins (already C-free);
// everything else shells out. Paths are double-quoted, so spaces are fine.

module fsx

// native trim() strips spaces only (not \n\r\t), so chomp exec output here.
func _chomp(s) {
    let lo = 0
    let hi = len(s)
    while lo < hi {
        let c = toInt(charCode(s[lo]))
        if c == 32 || c == 9 || c == 10 || c == 13 { lo += 1 } else { break }
    }
    while hi > lo {
        let c = toInt(charCode(s[hi - 1]))
        if c == 32 || c == 9 || c == 10 || c == 13 { hi -= 1 } else { break }
    }
    emit substring(s, lo, hi)
}

func _q(s) { emit "\"" + s + "\"" }
func _ok(cmd) { emit _chomp(exec("( " + cmd + " ) >/dev/null 2>&1 && echo 1 || echo 0")) }

// ── existence / type ─────────────────────────────────────────────────
func exists(p) { emit _ok("test -e " + _q(p)) }
func isDir(p)  { emit _ok("test -d " + _q(p)) }
func isFile(p) { emit _ok("test -f " + _q(p)) }

// ── listing ──────────────────────────────────────────────────────────
// listDir(p): names in p (one per line, incl. dotfiles, excl. . and ..).
// Iterate with lineCount()/getLine(). Empty string if dir is empty/missing.
func listDir(p) { emit exec("ls -1A " + _q(p) + " 2>/dev/null") }

// listFiles(p): only regular files under p (one per line, full paths).
func listFiles(p) {
    emit exec("find " + _q(p) + " -maxdepth 1 -type f 2>/dev/null")
}
// listDirs(p): only subdirectories under p (one per line, full paths).
func listDirs(p) {
    emit exec("find " + _q(p) + " -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
}
// glob(pattern): expand a shell glob (e.g. "*.k"), one match per line.
func glob(pattern) { emit exec("ls -1d " + pattern + " 2>/dev/null") }

// ── create / remove / move ───────────────────────────────────────────
func mkdirp(p)  { exec("mkdir -p " + _q(p))  emit "" }
func touch(p)   { exec("touch " + _q(p))     emit "" }
func rm(p)      { exec("rm -f " + _q(p))      emit "" }
func rmrf(p)    { exec("rm -rf " + _q(p))     emit "" }
func rmdir(p)   { exec("rmdir " + _q(p) + " 2>/dev/null")  emit "" }
func cp(src, dst)  { exec("cp " + _q(src) + " " + _q(dst))   emit "" }
func cpr(src, dst) { exec("cp -r " + _q(src) + " " + _q(dst)) emit "" }
func mv(src, dst)  { exec("mv " + _q(src) + " " + _q(dst))   emit "" }

// ── info ─────────────────────────────────────────────────────────────
// size(p): file size in bytes as an int (0 if missing).
func size(p) {
    let s = _chomp(exec("wc -c < " + _q(p) + " 2>/dev/null"))
    if s == "" { emit 0 }
    emit toInt(s)
}
func cwd()  { emit _chomp(exec("pwd")) }
func home() { emit _chomp(exec("printf '%s' \"$HOME\"")) }

// ── read / write (native builtins, already C-free) ───────────────────
func readText(p)  { emit readFile(p) }
func writeText(p, s) { writeFile(p, s)  emit "" }
// appendText: read-modify-write (writeFile truncates). Fine for small files.
func appendText(p, s) {
    let cur = ""
    if exists(p) == "1" { cur = readFile(p) }
    writeFile(p, cur + s)
    emit ""
}
