// Test pair operations (pairVal, pairPos)

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Pair Operation Tests")
    kp("====================")

    // Basic pair
    let p1 = "hello,5"
    check("pairVal basic", "hello", pairVal(p1))
    check("pairPos basic", "5", "" + pairPos(p1))

    // Numeric pair
    let p2 = "42,100"
    check("pairVal num", "42", pairVal(p2))
    check("pairPos num", "100", "" + pairPos(p2))

    // Create pair from values
    let val = "token"
    let pos = 15
    let p3 = val + "," + pos
    check("created pair val", "token", pairVal(p3))
    check("created pair pos", "15", "" + pairPos(p3))

    // Use in a function
    let p4 = "result,7"
    let v = pairVal(p4)
    let p = pairPos(p4)
    check("extract val", "result", v)
    check("extract pos", "7", "" + p)

    // Pair with zero position
    let p5 = "start,0"
    check("zero pos", "0", "" + pairPos(p5))

    emit "ok"
}
