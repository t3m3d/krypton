// sort_lines - Sort lines of a file alphabetically (bubble sort)

just run {
    if argCount() < 1 {
        kp("Usage: sort_lines <file>")
    } else {
        let content = readFile(arg(0))
        let lc = lineCount(content)

        // Load lines into comma-separated list
        let lines = ""
        let i = 0
        while i < lc {
            if i > 0 { lines = lines + "," }
            lines = lines + getLine(content, i)
            i = i + 1
        }

        // Bubble sort
        i = 0
        while i < lc - 1 {
            let j = 0
            while j < lc - 1 - i {
                let a = split(lines, j)
                let b = split(lines, j + 1)
                if a > b {
                    // Rebuild list with swapped elements
                    let sb = sbNew()
                    let k = 0
                    while k < lc {
                        if k > 0 { sb = sbAppend(sb, ",") }
                        if k == j {
                            sb = sbAppend(sb, b)
                        } else if k == j + 1 {
                            sb = sbAppend(sb, a)
                        } else {
                            sb = sbAppend(sb, split(lines, k))
                        }
                        k = k + 1
                    }
                    lines = sbToString(sb)
                }
                j = j + 1
            }
            i = i + 1
        }

        // Print sorted
        i = 0
        while i < lc {
            kp(split(lines, i))
            i = i + 1
        }
    }
}
