// stats - File statistics tool

func isBlankLine(line) {
    if len(line) == 0 { emit 1 }
    let i = 0
    while i < len(line) {
        let ch = line[i]
        if ch != " " && ch != "\t" {
            emit 0
        }
        i = i + 1
    }
    emit 1
}

just run {
    if argCount() < 1 {
        print("Usage: stats <file>")
    } else {
        let filename = arg(0)
        let content = readFile(filename)
        let lc = lineCount(content)
        let chars = len(content)
        let blank = 0
        let longest = 0
        let shortest = 999999
        let totalLen = 0

        let i = 0
        while i < lc {
            let line = getLine(content, i)
            let ll = len(line)
            totalLen = totalLen + ll
            if ll > longest { longest = ll }
            if ll < shortest { shortest = ll }
            if isBlankLine(line) { blank = blank + 1 }
            i = i + 1
        }

        print("File: " + filename)
        print("Characters: " + chars)
        print("Lines: " + lc)
        print("Blank lines: " + blank)
        print("Non-blank: " + (lc - blank))
        if lc > 0 {
            print("Longest line: " + longest + " chars")
            print("Shortest line: " + shortest + " chars")
            print("Avg line length: " + (totalLen / lc) + " chars")
        }
    }
}
