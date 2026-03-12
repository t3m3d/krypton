// Test comparison operators
// Verifies ==, !=, <, >, <=, >=

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func boolStr(val) {
    if val {
        emit "true"
    }
    emit "false"
}

just run {
    kp("Comparison Tests")
    kp("================")

    // Equality
    check("eq numbers", "true", boolStr(5 == 5))
    check("eq strings", "true", boolStr("abc" == "abc"))
    check("neq numbers", "true", boolStr(5 != 3))
    check("neq strings", "true", boolStr("abc" != "xyz"))
    check("eq diff", "false", boolStr(5 == 3))

    // Less than
    check("lt true", "true", boolStr(3 < 5))
    check("lt false", "false", boolStr(5 < 3))
    check("lt equal", "false", boolStr(5 < 5))

    // Greater than
    check("gt true", "true", boolStr(5 > 3))
    check("gt false", "false", boolStr(3 > 5))
    check("gt equal", "false", boolStr(5 > 5))

    // Less than or equal
    check("lte less", "true", boolStr(3 <= 5))
    check("lte equal", "true", boolStr(5 <= 5))
    check("lte greater", "false", boolStr(6 <= 5))

    // Greater than or equal
    check("gte greater", "true", boolStr(5 >= 3))
    check("gte equal", "true", boolStr(5 >= 5))
    check("gte less", "false", boolStr(3 >= 5))

    // String comparisons
    check("str eq", "true", boolStr("hello" == "hello"))
    check("str neq", "true", boolStr("hello" != "world"))

    emit "ok"
}
