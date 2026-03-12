// freq - Line frequency counter
// Shows how many times each unique line appears

just run {
    if argCount() < 1 {
        print("Usage: freq <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)
        let env = ""
        let uniqLines = ""
        let uniqCount = 0

        let i = 0
        while i < lc {
            let line = getLine(content, i)
            if len(line) > 0 {
                let prev = envGet(env, line)
                if len(prev) == 0 {
                    env = envSet(env, line, "1")
                    if uniqCount > 0 {
                        uniqLines = uniqLines + "," + line
                    } else {
                        uniqLines = line
                    }
                    uniqCount = uniqCount + 1
                } else {
                    env = envSet(env, line, "" + (toInt(prev) + 1))
                }
            }
            i = i + 1
        }

        // Print results
        i = 0
        while i < uniqCount {
            let line = split(uniqLines, i)
            let cnt = envGet(env, line)
            print("  " + cnt + " " + line)
            i = i + 1
        }
    }
}
