// replace - Find and replace text in a file

func contains(haystack, needle) {
    let i = 0
    while i <= len(haystack) - len(needle) {
        if substring(haystack, i, i + len(needle)) == needle {
            emit 1
        }
        i = i + 1
    }
    emit 0
}

func replaceAll(s, old, new) {
    let result = ""
    let i = 0
    while i <= len(s) - len(old) {
        if substring(s, i, i + len(old)) == old {
            result = result + new
            i = i + len(old)
        } else {
            result = result + s[i]
            i = i + 1
        }
    }
    // Remaining characters
    while i < len(s) {
        result = result + s[i]
        i = i + 1
    }
    emit result
}

just run {
    if argCount() < 3 {
        kp("Usage: replace <find> <replace> <file>")
    } else {
        let find = arg(0)
        let repl = arg(1)
        let content = readFile(arg(2))
        let lc = lineCount(content)
        let changes = 0
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if contains(line, find) {
                kp(replaceAll(line, find, repl))
                changes = changes + 1
            } else {
                kp(line)
            }
            i = i + 1
        }
        // Print to stderr-like output
        kp("(" + changes + " lines changed)")
    }
}
