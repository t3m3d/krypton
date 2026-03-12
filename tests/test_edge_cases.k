// Test edge cases for various operations

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Edge Case Tests")
    kp("===============")

    // Zero operations
    check("0 + 0", "0", "" + (0 + 0))
    check("0 * anything", "0", "" + (0 * 999))
    check("0 / 1", "0", "" + (0 / 1))
    check("0 % 5", "0", "" + (0 % 5))

    // Identity operations
    check("n + 0", "42", "" + (42 + 0))
    check("n * 1", "42", "" + (42 * 1))
    check("n / 1", "42", "" + (42 / 1))
    check("n - 0", "42", "" + (42 - 0))

    // Self operations
    check("n - n", "0", "" + (42 - 42))
    check("n / n", "1", "" + (42 / 42))
    check("n % n", "0", "" + (42 % 42))

    // Large numbers
    check("large add", "2000000", "" + (1000000 + 1000000))
    check("large mul", "1000000", "" + (1000 * 1000))

    // String edge cases
    check("single char len", "1", "" + len("x"))
    check("single char idx", "x", "x"[0])
    check("substr single", "a", substring("abc", 0, 1))

    // Boolean edge cases
    if 1 == 1 {
        check("1 == 1", "yes", "yes")
    }
    if 0 == 0 {
        check("0 == 0", "yes", "yes")
    }

    // Variable reassignment
    let x = 1
    x = 2
    x = 3
    check("reassign", "3", "" + x)

    emit "ok"
}
