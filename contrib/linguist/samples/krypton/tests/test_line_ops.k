// Test line operations (getLine, lineCount)

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Line Operation Tests")
    kp("====================")

    let text = "first\nsecond\nthird\nfourth\n"

    check("lineCount", "4", "" + lineCount(text))
    check("getLine 0", "first", getLine(text, 0))
    check("getLine 1", "second", getLine(text, 1))
    check("getLine 2", "third", getLine(text, 2))
    check("getLine 3", "fourth", getLine(text, 3))

    // Single line
    let single = "only line\n"
    check("single lineCount", "1", "" + lineCount(single))
    check("single getLine", "only line", getLine(single, 0))

    // Multi-line with empty lines
    let withEmpty = "a\n\nb\n\nc\n"
    check("with empty count", "5", "" + lineCount(withEmpty))
    check("with empty line 0", "a", getLine(withEmpty, 0))
    check("with empty line 1", "", getLine(withEmpty, 1))
    check("with empty line 2", "b", getLine(withEmpty, 2))

    emit "ok"
}
