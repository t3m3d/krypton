// stdlib/pathlib.k -- Python `pathlib` module surface on top of
// existing stdlib/os.k path helpers.
//
// Python's pathlib is class-based (Path objects).  Until Tier B
// classes ship, this exposes function-call equivalents named after
// the corresponding Path method.  The FE lowering treats
// `Path("foo").join("bar")` like `pathJoink("foo", "bar")` --
// receiver becomes first arg.
//
// FE lowering:
//   Path(p).name                -> pathNamek(p)
//   Path(p).stem                -> pathStemk(p)
//   Path(p).suffix              -> pathSuffixk(p)
//   Path(p).parent              -> pathParentk(p)
//   Path(p).parts               -> pathPartsk(p)
//   Path(p).exists()            -> pathExistsk(p)
//   Path(p).is_file()           -> pathIsFilek(p)
//   Path(p).is_dir()            -> pathIsDirk(p)
//   Path(p).joinpath(...)       -> pathJoinPathk(p, ...)
//   Path(p) / other             -> pathJoinPathk(p, other)
//   Path(p).read_text()         -> pathReadTextk(p)
//   Path(p).write_text(s)       -> pathWriteTextk(p, s)
//   Path(p).iterdir()           -> pathIterDirk(p)
//   Path(p).absolute()          -> pathAbsolutek(p)
//   Path(p).resolve()           -> pathResolvek(p)
//   Path.cwd()                  -> pathCwdk()
//   Path.home()                 -> pathHomek()

module pathlib

import "k:os"


// Path(p).name -- final path component (file name including extension).
func pathNamek(p) {
    emit ospathbasenamek(p)
}

// Path(p).stem -- file name without the final suffix.
func pathStemk(p) {
    let bn = ospathbasenamek(p)
    let parts = ospathsplitextk(bn)
    emit split(parts, 0)
}

// Path(p).suffix -- the file extension, including the dot.  "" if none.
func pathSuffixk(p) {
    let bn = ospathbasenamek(p)
    let parts = ospathsplitextk(bn)
    emit split(parts, 1)
}

// Path(p).suffixes -- all extensions, e.g. "tar.gz" -> ".tar,.gz"
func pathSuffixesk(p) {
    let bn = ospathbasenamek(p)
    // Walk forward collecting every "." onwards as a suffix until
    // we hit the first one.
    let out = sbNew()
    let i = 0
    let started = "0"
    let first = "1"
    while i < len(bn) {
        if bn[i] == "." {
            if first == "0" { out = sbAppend(out, ",") }
            // capture until next dot or end
            let lo = i
            let hi = i + 1
            while hi < len(bn) && bn[hi] != "." { hi += 1 }
            out = sbAppend(out, substring(bn, lo, hi))
            first = "0"
            i = hi
            started = "1"
        } else {
            i += 1
        }
    }
    emit sbToString(out)
}

// Path(p).parent -- the parent directory.
func pathParentk(p) {
    let d = ospathdirnamek(p)
    if d == "" { emit "." }
    emit d
}

// Path(p).parts -- the path components.  Windows: drive letter handled,
// then separator-split.
func pathPartsk(p) {
    let out = sbNew()
    let lo = 0
    let i = 0
    let first = "1"
    while i < len(p) {
        let c = p[i]
        if c == "\\" || c == "/" {
            if i > lo {
                if first == "0" { out = sbAppend(out, ",") }
                out = sbAppend(out, substring(p, lo, i))
                first = "0"
            }
            lo = i + 1
        }
        i += 1
    }
    if lo < len(p) {
        if first == "0" { out = sbAppend(out, ",") }
        out = sbAppend(out, substring(p, lo, len(p)))
    }
    emit sbToString(out)
}

// Path(p).exists()
func pathExistsk(p) {
    emit ospathexistsk(p)
}

// Path(p).is_file()  -- exists AND is not a directory.  Today: same
// as exists() because we have no Krypton-side directory check.  A
// follow-up wires GetFileAttributesA + FILE_ATTRIBUTE_DIRECTORY check.
func pathIsFilek(p) {
    emit ospathexistsk(p)
}

// Path(p).is_dir()  -- same shape, opposite check.  Stub today.
func pathIsDirk(p) {
    // Tentative: check if listing succeeds.
    if ospathexistsk(p) == 1 { emit 1 }
    emit 0
}

// Path(p).joinpath(...)  -- append components.
func pathJoinPathk(a, b) {
    emit ospathjoink(a, b)
}

// Path(p).read_text()  -- file contents as string.
func pathReadTextk(p) {
    emit readFile(p)
}

// Path(p).write_text(s)  -- write string to file.  Returns ""
// (Python returns char count; available via len(s) at the caller).
func pathWriteTextk(p, s) {
    writeFile(p, s)
    emit ""
}

// Path(p).iterdir()  -- directory entries as a comma-list.
func pathIterDirk(p) {
    emit oslistdirk(p)
}

// Path(p).absolute()  -- resolve to absolute path.  Today: if already
// has a drive letter or starts with /, return as-is; else prepend
// cwd.  Real impl uses GetFullPathNameA.
func pathAbsolutek(p) {
    if len(p) >= 2 && p[1] == ":" { emit p }  // C:... already absolute
    if len(p) > 0 && (p[0] == "\\" || p[0] == "/") { emit p }  // Unix-style absolute
    emit ospathjoink(osgetcwdk(), p)
}

// Path(p).resolve()  -- same as absolute for now; symlink resolution
// requires GetFinalPathNameByHandleA which isn't wired.
func pathResolvek(p) {
    emit pathAbsolutek(p)
}

// Path.cwd()  -- current working directory.
func pathCwdk() {
    emit osgetcwdk()
}

// Path.home()  -- user home dir.
func pathHomek() {
    let p = osgetenvk("USERPROFILE", "")
    if p != "" { emit p }
    emit osgetenvk("HOME", "")
}

// pathlib.Path(p).mkdir(parents=True, exist_ok=True)  -- create dirs.
func pathMkdirk(p) {
    osmkdirk(p)
    emit ""
}

// pathlib.PurePath -- pure-string manipulation, no file system access.
// Same surface as Path for our purposes since we don't enforce the
// distinction.  All the methods above are usable on either.
