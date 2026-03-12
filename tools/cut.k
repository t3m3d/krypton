// cut - Extract fields from comma-separated lines

just run {
    if argCount() < 2 {
        print("Usage: cut <field_index> <file>")
    } else {
        let field = toInt(arg(0))
        let content = readFile(arg(1))
        let lc = lineCount(content)
        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if len(line) > 0 {
                let fc = count(line)
                if field < fc {
                    print(split(line, field))
                } else {
                    print("")
                }
            }
            i = i + 1
        }
    }
}
