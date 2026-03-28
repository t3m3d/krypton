// test_closure.k — True closure tests

func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

func makeMultiplier(factor) {
    emit func(x) { emit toInt(x) * toInt(factor) + "" }
}

just run {
    // Basic closure - captures outer variable
    let add5 = makeAdder("5")
    if add5("3") == "8"  { kp("PASS closure add5(3)") } else { kp("FAIL: " + add5("3")) }
    if add5("10") == "15" { kp("PASS closure add5(10)") } else { kp("FAIL: " + add5("10")) }

    // Different closure instance
    let add10 = makeAdder("10")
    if add10("7") == "17" { kp("PASS closure add10(7)") } else { kp("FAIL: " + add10("7")) }

    // Multiplier closure
    let triple = makeMultiplier("3")
    if triple("4") == "12" { kp("PASS closure triple(4)") } else { kp("FAIL: " + triple("4")) }

    kp("ALL CLOSURE TESTS PASSED")
}
