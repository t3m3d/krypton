// Test startsWith function

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("startsWith Tests")
    kp("================")

    check("basic yes", "1", "" + startsWith("hello world", "hello"))
    check("basic no", "0", "" + startsWith("hello world", "world"))
    check("empty prefix", "1", "" + startsWith("hello", ""))
    check("exact match", "1", "" + startsWith("hello", "hello"))
    check("longer prefix", "0", "" + startsWith("hi", "hello"))
    check("single char yes", "1", "" + startsWith("hello", "h"))
    check("single char no", "0", "" + startsWith("hello", "x"))
    check("number prefix", "1", "" + startsWith("123abc", "123"))
    check("special chars", "1", "" + startsWith("//comment", "//"))
    check("case sensitive", "0", "" + startsWith("Hello", "hello"))

    emit "ok"
}
