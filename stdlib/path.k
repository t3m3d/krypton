// Path manipulation utilities for Krypton

go path {

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
}
