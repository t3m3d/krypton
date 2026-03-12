// fmt - Simple text formatter
// Strips leading/trailing whitespace and normalizes blank lines

func trimLine(line) {
    let start = 0
    while start < len(line) {
        let ch = line[start]
        if ch != " " && ch != "\t" {
            break
        }
        start = start + 1
    }
    let end = len(line)
    while end > start {
        let ch = line[end - 1]
        if ch != " " && ch != "\t" {
            break
        }
        end = end - 1
    }
    emit substring(line, start, end)
}

just run {
    if argCount() < 1 {
        print("Usage: fmt <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let prevBlank = 0
        let i = 0
        while i < lc {
            let line = trimLine(getLine(content, i))
            if len(line) == 0 {
                if !prevBlank {
                    print("")
                    prevBlank = 1
                }
            } else {
                print(line)
                prevBlank = 0
            }
            i = i + 1
        }
    }
}
