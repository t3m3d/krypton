// fold - Wrap long lines at specified width

func wrapLine(line, width) {
    let sb = sbNew()
    let i = 0
    while i < len(line) {
        let end = i + width
        if end > len(line) { end = len(line) }
        if i > 0 {
            sb = sbAppend(sb, "\n")
        }
        sb = sbAppend(sb, substring(line, i, end))
        i = i + width
    }
    emit sbToString(sb)
}

just run {
    if argCount() < 1 {
        kp("Usage: fold <file> [width]")
    } else {
        let width = 80
        if argCount() >= 2 {
            width = toInt(arg(1))
        }
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if len(line) <= width {
                kp(line)
            } else {
                kp(wrapLine(line, width))
            }
            i = i + 1
        }
    }
}
