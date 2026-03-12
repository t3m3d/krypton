// Test function calls and return values

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func add(a, b) { emit a + b }
func mul(a, b) { emit a * b }
func identity(x) { emit x }
func constant() { emit 42 }
func nested(x) { emit add(x, mul(x, 2)) }

func buildStr(n) {
    let sb = sbNew()
    let i = 0
    while i < n {
        sb = sbAppend(sb, "x")
        i = i + 1
    }
    emit sbToString(sb)
}

func chain(a, b, c) {
    let x = add(a, b)
    let y = mul(x, c)
    emit y
}

just run {
    kp("Function Call Tests")
    kp("===================")

    check("add", "5", "" + add(2, 3))
    check("mul", "12", "" + mul(3, 4))
    check("identity num", "7", "" + identity(7))
    check("identity str", "hello", identity("hello"))
    check("constant", "42", "" + constant())

    // Nested calls
    check("nested call", "9", "" + nested(3))
    check("call in call", "7", "" + add(add(1, 2), add(1, 3)))

    // Function as argument
    check("chain", "15", "" + chain(2, 3, 3))

    // String building function
    check("buildStr 5", "xxxxx", buildStr(5))
    check("buildStr 0", "", buildStr(0))

    // Multiple return paths
    check("add result used", "10", "" + add(add(1, 2), add(3, 4)))

    emit "ok"
}
