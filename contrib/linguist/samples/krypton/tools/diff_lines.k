// diff_lines - Compare two files line by line

just run {
    if argCount() < 2 {
        kp("Usage: diff_lines <file1> <file2>")
    } else {
        let c1 = readFile(arg(0))
        let c2 = readFile(arg(1))
        let lc1 = lineCount(c1)
        let lc2 = lineCount(c2)
        let maxLines = lc1
        if lc2 > maxLines { maxLines = lc2 }
        let diffs = 0

        let i = 0
        while i < maxLines {
            let l1 = ""
            let l2 = ""
            if i < lc1 { l1 = getLine(c1, i) }
            if i < lc2 { l2 = getLine(c2, i) }

            if l1 != l2 {
                kp("Line " + (i + 1) + ":")
                kp("  < " + l1)
                kp("  > " + l2)
                diffs = diffs + 1
            }
            i = i + 1
        }

        if diffs == 0 {
            kp("Files are identical")
        } else {
            kp("" + diffs + " line(s) differ")
        }
    }
}
