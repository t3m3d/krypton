// Test logical operators
// Verifies &&, ||, and !

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func boolStr(val) {
    if val { emit "true" }
    emit "false"
}

just run {
    kp("Logical Operator Tests")
    kp("======================")

    // AND
    check("and TT", "true", boolStr(1 && 1))
    check("and TF", "false", boolStr(1 && 0))
    check("and FT", "false", boolStr(0 && 1))
    check("and FF", "false", boolStr(0 && 0))

    // OR
    check("or TT", "true", boolStr(1 || 1))
    check("or TF", "true", boolStr(1 || 0))
    check("or FT", "true", boolStr(0 || 1))
    check("or FF", "false", boolStr(0 || 0))

    // NOT
    check("not true", "false", boolStr(!1))
    check("not false", "true", boolStr(!0))

    // Combined
    check("and-or 1", "true", boolStr(1 && 1 || 0))
    check("and-or 2", "true", boolStr(0 || 1 && 1))
    check("not-and", "false", boolStr(!1 && 1))
    check("not-or", "true", boolStr(!0 || 0))

    // With comparisons
    check("cmp and", "true", boolStr(5 > 3 && 10 > 7))
    check("cmp or", "true", boolStr(5 > 10 || 3 < 7))
    check("cmp complex", "true", boolStr((5 == 5) && (3 != 4)))

    emit "ok"
}
