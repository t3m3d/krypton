// Test integer division

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Division Tests")
    kp("==============")

    check("10 / 2", "5", "" + (10 / 2))
    check("10 / 3", "3", "" + (10 / 3))
    check("100 / 10", "10", "" + (100 / 10))
    check("7 / 2", "3", "" + (7 / 2))
    check("1 / 2", "0", "" + (1 / 2))
    check("0 / 5", "0", "" + (0 / 5))
    check("42 / 1", "42", "" + (42 / 1))
    check("99 / 10", "9", "" + (99 / 10))
    check("1000000 / 1000", "1000", "" + (1000000 / 1000))

    // Division and modulo relationship: a = (a/b)*b + (a%b)
    let a = 17
    let b = 5
    let q = a / b
    let r = a % b
    check("div-mod identity", "" + a, "" + (q * b + r))

    a = 100
    b = 7
    q = a / b
    r = a % b
    check("div-mod identity 2", "" + a, "" + (q * b + r))

    emit "ok"
}
