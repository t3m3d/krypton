// Test file reading operations

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("File Read Tests")
    kp("===============")

    // Read our own source file and verify properties
    if argCount() >= 1 {
        let content = readFile(arg(0))
        let lc = lineCount(content)

        // Verify we read something
        let hasContent = 0
        if len(content) > 0 {
            hasContent = 1
        }
        check("file not empty", "1", "" + hasContent)

        // Verify line count is reasonable
        let hasLines = 0
        if lc > 5 {
            hasLines = 1
        }
        check("has multiple lines", "1", "" + hasLines)

        // Verify first line
        let firstLine = getLine(content, 0)
        check("first line is comment", "1", "" + startsWith(firstLine, "//"))
    } else {
        kp("[SKIP] No file argument provided")
    }

    emit "ok"
}
