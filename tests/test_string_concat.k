// Test string concatenation edge cases

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("String Concatenation Tests")
    kp("==========================")

    // Basic concat
    check("two strings", "ab", "a" + "b")
    check("three strings", "abc", "a" + "b" + "c")
    check("with space", "a b", "a" + " " + "b")

    // Number to string
    check("num concat", "x42", "x" + 42)
    check("num concat 2", "42x", "" + 42 + "x")
    // Per spec: numeric strings always add via `+`, even toStr-converted ones.
    // To force string concat of numeric tokens, build via sbAppend.
    let _sb = sbNew()
    _sb = sbAppend(_sb, "1")
    _sb = sbAppend(_sb, "2")
    _sb = sbAppend(_sb, "3")
    check("two nums str", "123", sbToString(_sb))

    // Empty string concat
    check("empty left", "hello", "" + "hello")
    check("empty right", "hello", "hello" + "")
    check("both empty", "", "" + "")

    // Long concat chain
    let s = ""
    let i = 0
    while i < 10 {
        s = s + "a"
        i = i + 1
    }
    check("chain 10", "10", "" + len(s))

    // Mixed types
    check("mixed 1", "value: 42", "value: " + 42)
    check("mixed 2", "result=100", "result=" + 100)

    // Concat in condition
    let name = "world"
    check("in condition", "hello world", "hello " + name)

    emit "ok"
}
