// Test substring function
// Verifies various substring extractions

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Substring Tests")
    kp("===============")

    let s = "Hello, World!"

    check("full string", "Hello, World!", substring(s, 0, 13))
    check("first word", "Hello", substring(s, 0, 5))
    check("comma", ",", substring(s, 5, 6))
    check("space", " ", substring(s, 6, 7))
    check("second word", "World", substring(s, 7, 12))
    check("exclaim", "!", substring(s, 12, 13))
    check("empty range", "", substring(s, 5, 5))
    check("single char", "H", substring(s, 0, 1))
    check("last char", "!", substring(s, 12, 13))
    check("middle", "lo, Wo", substring(s, 3, 9))

    // Substring of digits
    let digits = "0123456789"
    check("digits 0-3", "012", substring(digits, 0, 3))
    check("digits 5-8", "567", substring(digits, 5, 8))
    check("digits all", "0123456789", substring(digits, 0, 10))

    // Nested substring
    let sub = substring(s, 0, 5)
    check("nested", "ell", substring(sub, 1, 4))

    emit "ok"
}
