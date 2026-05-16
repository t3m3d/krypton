// Test modulo operation

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Modulo Tests")
    kp("============")

    check("10 % 3", "1", "" + (10 % 3))
    check("10 % 2", "0", "" + (10 % 2))
    check("7 % 4", "3", "" + (7 % 4))
    check("100 % 7", "2", "" + (100 % 7))
    check("5 % 5", "0", "" + (5 % 5))
    check("1 % 5", "1", "" + (1 % 5))
    check("0 % 5", "0", "" + (0 % 5))
    check("15 % 4", "3", "" + (15 % 4))
    check("999 % 10", "9", "" + (999 % 10))

    // Even/Odd check using modulo
    let i = 0
    let evenCount = 0
    let oddCount = 0
    while i < 10 {
        if i % 2 == 0 {
            evenCount = evenCount + 1
        } else {
            oddCount = oddCount + 1
        }
        i = i + 1
    }
    check("even count 0-9", "5", "" + evenCount)
    check("odd count 0-9", "5", "" + oddCount)

    emit "ok"
}
