// head - Print first N lines of a file

just run {
    if argCount() < 1 {
        print("Usage: head <file> [n]")
    } else {
        let filename = arg(0)
        let n = 10
        if argCount() >= 2 {
            n = toInt(arg(1))
        }
        let content = readFile(filename)
        let lc = lineCount(content)
        if n > lc { n = lc }
        let i = 0
        while i < n {
            print(getLine(content, i))
            i = i + 1
        }
    }
}
