// grep - Search for lines matching a prefix pattern

just run {
    if argCount() < 2 {
        kp("Usage: grep <pattern> <file>")
    } else {
        let pattern = arg(0)
        let filename = arg(1)
        let content = readFile(filename)
        let lc = lineCount(content)
        let matches = 0
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            // Simple contains check: scan for pattern in line
            let j = 0
            let found = 0
            while j <= len(line) - len(pattern) {
                if substring(line, j, j + len(pattern)) == pattern {
                    found = 1
                    break
                }
                j = j + 1
            }
            if found {
                kp(line)
                matches = matches + 1
            }
            i = i + 1
        }
        if matches == 0 {
            kp("No matches found.")
        }
    }
}
