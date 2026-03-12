// uniq - Remove consecutive duplicate lines

just run {
    if argCount() < 1 {
        print("Usage: uniq <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let prev = ""
        let first = 1
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if first || line != prev {
                print(line)
                first = 0
            }
            prev = line
            i = i + 1
        }
    }
}
