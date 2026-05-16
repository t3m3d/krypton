// nl - Number lines of a file

just run {
    if argCount() < 1 {
        kp("Usage: nl <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let i = 0
        while i < lc {
            let num = i + 1
            // Right-align the number
            let prefix = ""
            if num < 10 { prefix = "     " }
            else if num < 100 { prefix = "    " }
            else if num < 1000 { prefix = "   " }
            else if num < 10000 { prefix = "  " }
            else { prefix = " " }
            kp(prefix + num + "  " + getLine(content, i))
            i = i + 1
        }
    }
}
