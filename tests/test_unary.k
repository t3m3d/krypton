// Test unary operators

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Unary Operator Tests")
    kp("====================")

    // Unary negation
    let x = 5
    let negX = 0 - x
    check("negate var", "-5", "" + negX)
    check("double negate", "5", "" + (0 - negX))

    // Logical NOT
    check("not 0", "1", "" + !0)
    check("not 1", "0", "" + !1)
    check("not not 1", "1", "" + !!1)
    check("not not 0", "0", "" + !!0)

    // NOT with comparisons
    let a = 5
    let b = 3
    if !(a == b) {
        check("not equal", "yes", "yes")
    } else {
        check("not equal", "yes", "no")
    }

    if !(a < b) {
        check("not less", "yes", "yes")
    } else {
        check("not less", "yes", "no")
    }

    // NOT with boolean expressions
    if !(0) {
        check("not falsy", "truthy", "truthy")
    } else {
        check("not falsy", "truthy", "falsy")
    }

    emit "ok"
}
