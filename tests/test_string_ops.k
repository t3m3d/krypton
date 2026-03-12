// Test string operations
// Verifies string concatenation, indexing, and built-in functions

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("String Operations Tests")
    kp("=======================")

    // Concatenation
    check("concat basic", "hello world", "hello" + " " + "world")
    check("concat empty", "abc", "" + "abc")
    check("concat numbers", "12", "" + 1 + 2)

    // Length
    check("len empty", "0", "" + len(""))
    check("len hello", "5", "" + len("hello"))
    check("len spaces", "3", "" + len("   "))

    // Indexing
    check("index 0", "h", "hello"[0])
    check("index 4", "o", "hello"[4])
    check("index middle", "l", "hello"[2])

    // Substring
    check("substr full", "hello", substring("hello", 0, 5))
    check("substr part", "ell", substring("hello", 1, 4))
    check("substr single", "h", substring("hello", 0, 1))
    check("substr empty", "", substring("hello", 2, 2))

    // startsWith
    check("starts yes", "1", "" + startsWith("hello", "hel"))
    check("starts no", "0", "" + startsWith("hello", "xyz"))
    check("starts empty", "1", "" + startsWith("hello", ""))

    emit "ok"
}
