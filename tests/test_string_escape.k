// Test string escape sequences

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("String Escape Tests")
    kp("===================")

    // Newline
    let nl = "a\nb"
    check("newline len", "3", "" + len(nl))
    check("newline char", "a", nl[0])
    check("newline char 2", "b", nl[2])

    // Tab
    let tab = "a\tb"
    check("tab len", "3", "" + len(tab))

    // Backslash
    let bs = "a\\b"
    check("backslash len", "3", "" + len(bs))
    check("backslash char", "\\", bs[1])

    // Quote
    let qt = "a\"b"
    check("quote len", "3", "" + len(qt))

    // Multiple escapes
    let multi = "line1\nline2\nline3"
    check("multi lines", "3", "" + lineCount(multi + "\n"))

    // Empty with escape
    let justNL = "\n"
    check("just newline", "1", "" + len(justNL))

    emit "ok"
}
