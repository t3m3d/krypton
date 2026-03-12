// Test boolean values and truthiness

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func isTruthy(val) {
    if val {
        emit "truthy"
    }
    emit "falsy"
}

just run {
    kp("Boolean/Truthiness Tests")
    kp("========================")

    // True/false literals
    check("true is truthy", "truthy", isTruthy(1))
    check("false is falsy", "falsy", isTruthy(0))

    // Number truthiness
    check("1 truthy", "truthy", isTruthy(1))
    check("0 falsy", "falsy", isTruthy(0))
    check("42 truthy", "truthy", isTruthy(42))

    // String truthiness
    check("non-empty truthy", "truthy", isTruthy("hello"))
    check("empty falsy", "falsy", isTruthy(""))

    // Comparison results
    check("eq true", "truthy", isTruthy(5 == 5))
    check("eq false", "falsy", isTruthy(5 == 3))
    check("gt true", "truthy", isTruthy(5 > 3))
    check("gt false", "falsy", isTruthy(3 > 5))

    // Boolean in conditions
    let val = 5 > 3
    if val {
        check("bool var", "yes", "yes")
    } else {
        check("bool var", "yes", "no")
    }

    emit "ok"
}
