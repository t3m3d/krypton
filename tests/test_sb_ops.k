// Test string builder operations (sbNew, sbAppend, sbToString)

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("String Builder Tests")
    kp("====================")

    // Basic usage
    let sb = sbNew()
    sb = sbAppend(sb, "hello")
    sb = sbAppend(sb, " ")
    sb = sbAppend(sb, "world")
    check("basic build", "hello world", sbToString(sb))

    // Empty builder
    let empty = sbNew()
    check("empty builder", "", sbToString(empty))

    // Single append
    let single = sbNew()
    single = sbAppend(single, "only")
    check("single append", "only", sbToString(single))

    // Many appends
    let many = sbNew()
    let i = 0
    while i < 5 {
        many = sbAppend(many, "a")
        i = i + 1
    }
    check("many appends", "aaaaa", sbToString(many))
    check("many len", "5", "" + len(sbToString(many)))

    // Build numbers
    let nums = sbNew()
    i = 1
    while i <= 5 {
        if i > 1 {
            nums = sbAppend(nums, ",")
        }
        nums = sbAppend(nums, "" + i)
        i = i + 1
    }
    check("build nums", "1,2,3,4,5", sbToString(nums))

    // Append newlines
    let lines = sbNew()
    lines = sbAppend(lines, "line1\n")
    lines = sbAppend(lines, "line2\n")
    let result = sbToString(lines)
    check("lines count", "2", "" + lineCount(result))

    emit "ok"
}
