// Test len function
// Verifies string length measurement

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Length Tests")
    kp("===========")

    check("empty", "0", "" + len(""))
    check("one char", "1", "" + len("a"))
    check("hello", "5", "" + len("hello"))
    check("spaces", "3", "" + len("   "))
    check("digits", "10", "" + len("0123456789"))
    check("mixed", "11", "" + len("hello world"))
    check("newline", "2", "" + len("a\n"))
    check("tab", "2", "" + len("a\t"))

    // Length of number converted to string
    check("num 0", "1", "" + len("" + 0))
    check("num 1", "1", "" + len("" + 1))
    check("num 10", "2", "" + len("" + 10))
    check("num 100", "3", "" + len("" + 100))
    check("num 1000", "4", "" + len("" + 1000))

    // Length after operations
    let a = "hello"
    let b = " world"
    check("concat len", "11", "" + len(a + b))
    check("substr len", "3", "" + len(substring(a, 1, 4)))

    emit "ok"
}
