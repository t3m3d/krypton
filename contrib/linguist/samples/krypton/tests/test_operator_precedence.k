// Test operator precedence

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Operator Precedence Tests")
    kp("=========================")

    // Multiplication before addition
    check("2 + 3 * 4", "14", "" + (2 + 3 * 4))
    check("2 * 3 + 4", "10", "" + (2 * 3 + 4))

    // Division before subtraction
    check("10 - 6 / 2", "7", "" + (10 - 6 / 2))

    // Parentheses override
    check("(2 + 3) * 4", "20", "" + ((2 + 3) * 4))
    check("2 * (3 + 4)", "14", "" + (2 * (3 + 4)))

    // Multiple levels
    check("1 + 2 * 3 + 4", "11", "" + (1 + 2 * 3 + 4))
    check("(1 + 2) * (3 + 4)", "21", "" + ((1 + 2) * (3 + 4)))

    // Comparison with arithmetic
    let r1 = 2 + 3 > 4
    if r1 {
        check("2+3 > 4", "true", "true")
    } else {
        check("2+3 > 4", "true", "false")
    }

    let r2 = 2 * 3 == 6
    if r2 {
        check("2*3 == 6", "true", "true")
    } else {
        check("2*3 == 6", "true", "false")
    }

    emit "ok"
}
