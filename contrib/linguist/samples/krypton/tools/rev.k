// rev - Reverse each line of a file

func reverseStr(s) {
    let result = ""
    let i = len(s) - 1
    while i >= 0 {
        result = result + s[i]
        i = i - 1
    }
    emit result
}

just run {
    if argCount() < 1 {
        kp("Usage: rev <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let i = 0
        while i < lc {
            kp(reverseStr(getLine(content, i)))
            i = i + 1
        }
    }
}
