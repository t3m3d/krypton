// cat - Concatenate and print files

just run {
    if argCount() < 1 {
        kp("Usage: cat <file> [file2] ...")
    } else {
        let i = 0
        while i < argCount() {
            let content = readFile(arg(i))
            let lc = lineCount(content)
            let j = 0
            while j < lc {
                kp(getLine(content, j))
                j = j + 1
            }
            i = i + 1
        }
    }
}
