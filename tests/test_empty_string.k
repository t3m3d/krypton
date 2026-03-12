// Test empty string edge cases

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Empty String Tests")
    kp("==================")

    let empty = ""

    check("len empty", "0", "" + len(empty))
    check("concat empty", "", empty + empty)
    check("concat with str", "hello", empty + "hello")
    check("startsWith empty", "1", "" + startsWith("hello", empty))
    check("substr empty", "", substring("hello", 2, 2))

    // Empty in conditions
    if empty {
        check("empty falsy", "false", "true")
    } else {
        check("empty falsy", "false", "false")
    }

    // Empty comparison
    check("empty eq empty", "1", "" + (empty == ""))
    check("empty neq str", "1", "" + (empty != "x"))

    // Building from empty
    let s = ""
    s = s + "a"
    s = s + "b"
    s = s + "c"
    check("build from empty", "abc", s)
    check("build len", "3", "" + len(s))

    emit "ok"
}
