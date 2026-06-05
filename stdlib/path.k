// Path manipulation utilities for Krypton

module path


// Join two path segments
func pathJoin(a, b) {
    if len(a) == 0 {
        emit b
    }
    if len(b) == 0 {
        emit a
    }
    let lastChar = a[len(a) - 1]
    if lastChar == "/" {
        emit a + b
    }
    if lastChar == "\\" {
        emit a + b
    }
    emit a + "/" + b
}

// Normalize path separators to forward slash
func normalizePath(p) {
    let sb = sbNew()
    let i = 0
    while i < len(p) {
        if p[i] == "\\" {
            sb = sbAppend(sb, "/")
        } else {
            sb = sbAppend(sb, p[i])
        }
        i += 1
    }
    emit sbToString(sb)
}

// Check if path is absolute
func isAbsolute(p) {
    if len(p) == 0 {
        emit 0
    }
    if p[0] == "/" {
        emit 1
    }
    // Check for Windows drive letter
    if len(p) >= 2 {
        if p[1] == ":" {
            emit 1
        }
    }
    emit 0
}

// Get parent directory
func parentDir(p) {
    let i = len(p) - 1
    // Skip trailing separator
    if i >= 0 {
        if p[i] == "/" {
            i -= 1
        }
        if p[i] == "\\" {
            i -= 1
        }
    }
    while i >= 0 {
        if p[i] == "/" {
            emit substring(p, 0, i)
        }
        if p[i] == "\\" {
            emit substring(p, 0, i)
        }
        i -= 1
    }
    emit "."
}

// Get file name without extension
func stem(p) {
    // First get the basename
    let name = p
    let i = len(p) - 1
    while i >= 0 {
        if p[i] == "/" {
            name = substring(p, i + 1, len(p))
            break
        }
        if p[i] == "\\" {
            name = substring(p, i + 1, len(p))
            break
        }
        i -= 1
    }
    // Remove extension
    i = len(name) - 1
    while i >= 0 {
        if name[i] == "." {
            emit substring(name, 0, i)
        }
        i -= 1
    }
    emit name
}

// Get file extension with dot
func extension(p) {
    let i = len(p) - 1
    while i >= 0 {
        if p[i] == "." {
            emit substring(p, i, len(p))
        }
        if p[i] == "/" {
            emit ""
        }
        if p[i] == "\\" {
            emit ""
        }
        i -= 1
    }
    emit ""
}

// Count path depth (number of separators)
func pathDepth(p) {
    let cnt = 0
    let i = 0
    while i < len(p) {
        if p[i] == "/" {
            cnt += 1
        }
        if p[i] == "\\" {
            cnt += 1
        }
        i += 1
    }
    emit cnt
}

// Basename — final path component, e.g. "a/b/c.txt" → "c.txt".
// Mirrors POSIX basename; honors both "/" and "\".
func basename(p) {
    let i = len(p) - 1
    while i >= 0 {
        if p[i] == "/" || p[i] == "\\" { emit substring(p, i + 1, len(p)) }
        i -= 1
    }
    emit p
}

// Replace an extension. newExt may include the leading "." or not.
//   changeExt("a/b/c.txt", "md")  → "a/b/c.md"
//   changeExt("a/b/c.txt", ".md") → "a/b/c.md"
//   changeExt("a/b/c",     "md")  → "a/b/c.md"
func changeExt(p, newExt) {
    let ext = extension(p)
    let base = p
    if len(ext) > 0 { base = substring(p, 0, len(p) - len(ext)) }
    let dot = ""
    if len(newExt) > 0 && newExt[0] != "." { dot = "." }
    let b = sbNew()
    b = sbAppend(b, base)
    b = sbAppend(b, dot)
    b = sbAppend(b, newExt)
    emit sbToString(b)
}

// Replace all "\" with "/" — friendly alias for normalizePath.
func toForwardSlashes(p) { emit normalizePath(p) }

// Replace all "/" with "\".
func toBackslashes(p) {
    let sb = sbNew()
    let i = 0
    while i < len(p) {
        if p[i] == "/" { sb = sbAppend(sb, "\\") }
        else           { sb = sbAppend(sb, p[i]) }
        i = i + 1
    }
    emit sbToString(sb)
}

// Split a Windows path's drive letter from the rest.
// Returns a tab-separated string "<drive>\t<rest>" — e.g.
//   splitDrive("C:/x/y")  → "C:\tx/y"
//   splitDrive("/abs/x")  → "\t/abs/x"   (no drive)
//   splitDrive("rel/p")   → "\trel/p"
func splitDrive(p) {
    if len(p) >= 2 && p[1] == ":" {
        let b = sbNew()
        b = sbAppend(b, substring(p, 0, 2))
        b = sbAppend(b, fromCharCode(9))
        b = sbAppend(b, substring(p, 2, len(p)))
        emit sbToString(b)
    }
    let b = sbNew()
    b = sbAppend(b, fromCharCode(9))
    b = sbAppend(b, p)
    emit sbToString(b)
}

// True ("1") iff `path` lives under `dir` (after slash normalisation
// and ensuring `dir` ends with "/"). Cheap textual check — does NOT
// resolve symlinks.
func isWithin(path, dir) {
    let np = normalizePath(path)
    let nd = normalizePath(dir)
    if len(nd) == 0 { emit "0" }
    if nd[len(nd) - 1] != "/" {
        let b = sbNew()
        b = sbAppend(b, nd)
        b = sbAppend(b, "/")
        nd = sbToString(b)
    }
    if len(np) < len(nd) { emit "0" }
    if substring(np, 0, len(nd)) == nd { emit "1" }
    emit "0"
}
