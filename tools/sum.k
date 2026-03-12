// sum - Sum numbers from a file (one per line)

just run {
    if argCount() < 1 {
        print("Usage: sum <file>")
        print("File should contain one number per line")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let total = 0
        let count = 0
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if len(line) > 0 {
                total = total + toInt(line)
                count = count + 1
            }
            i = i + 1
        }
        print("Lines: " + count)
        print("Sum: " + total)
    }
}
