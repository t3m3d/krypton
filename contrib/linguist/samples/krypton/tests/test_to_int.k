// Test toInt function

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("toInt Tests")
    kp("===========")

    check("zero", "0", "" + toInt("0"))
    check("one", "1", "" + toInt("1"))
    check("ten", "10", "" + toInt("10"))
    check("hundred", "100", "" + toInt("100"))
    check("large", "999999", "" + toInt("999999"))

    // Arithmetic with toInt
    let a = toInt("10")
    let b = toInt("20")
    check("toInt add", "30", "" + (a + b))
    check("toInt mul", "200", "" + (a * b))
    check("toInt sub", "10", "" + (b - a))

    // Converting back and forth
    let num = 42
    let str = "" + num
    let back = toInt(str)
    check("roundtrip", "42", "" + back)

    emit "ok"
}
