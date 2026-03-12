// Test string indexing
// Verifies character access by index

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("String Indexing Tests")
    kp("====================")

    let s = "abcdefghij"

    check("index 0", "a", s[0])
    check("index 1", "b", s[1])
    check("index 5", "f", s[5])
    check("index 9", "j", s[9])

    // Access through variable
    let idx = 3
    check("var index", "d", s[idx])

    // Computed index
    check("computed index", "e", s[2 + 2])

    // Single char string
    let ch = "X"
    check("single char", "X", ch[0])

    // Digits
    let digits = "0123456789"
    let i = 0
    while i < 10 {
        check("digit " + i, "" + i, digits[i])
        i = i + 1
    }

    // Mixed content
    let mixed = "a1b2c3"
    check("mixed 0", "a", mixed[0])
    check("mixed 1", "1", mixed[1])
    check("mixed 4", "c", mixed[4])
    check("mixed 5", "3", mixed[5])

    emit "ok"
}
