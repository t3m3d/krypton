// Tutorial 18: Working with Lines
// Processing multi-line text

just run {
    // Multi-line strings use \n
    let text = "first line\nsecond line\nthird line\nfourth line\n"

    // lineCount counts lines
    let lc = lineCount(text)
    kp("Line count: " + lc)

    // getLine gets a specific line (0-indexed)
    let i = 0
    while i < lc {
        let line = getLine(text, i)
        kp("[" + i + "] " + line)
        i = i + 1
    }

    // Filtering lines
    kp("\nLines containing 'second' or 'third':")
    i = 0
    while i < lc {
        let line = getLine(text, i)
        if startsWith(line, "second") || startsWith(line, "third") {
            kp("  > " + line)
        }
        i = i + 1
    }

    // Building new text from lines
    let sb = sbNew()
    i = 0
    while i < lc {
        let line = getLine(text, i)
        sb = sbAppend(sb, "" + (i + 1) + ": " + line + "\n")
        i = i + 1
    }
    kp("\nNumbered:")
    kp(sbToString(sb))
}
