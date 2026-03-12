// Test negative numbers

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Negative Number Tests")
    kp("=====================")

    // Negation
    check("negate 5", "-5", "" + (0 - 5))
    check("negate -5", "5", "" + (0 - (0 - 5)))

    // Arithmetic with negatives
    check("add neg", "2", "" + (5 + (0 - 3)))
    check("sub neg", "8", "" + (5 - (0 - 3)))
    check("mul neg", "-15", "" + ((0 - 3) * 5))

    // Comparisons with negatives
    let neg = 0 - 5
    if neg < 0 {
        check("neg lt zero", "true", "true")
    } else {
        check("neg lt zero", "true", "false")
    }

    if neg < 5 {
        check("neg lt pos", "true", "true")
    } else {
        check("neg lt pos", "true", "false")
    }

    // Negative in functions
    let a = 0 - 10
    let b = 3
    check("neg + pos", "-7", "" + (a + b))
    check("neg * pos", "-30", "" + (a * b))

    emit "ok"
}
