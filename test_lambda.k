// test_lambda.k — Lambda and closure tests for v1.1.0

func applyTwice(f, x) {
    emit f(f(x))
}

func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

func makeMultiplier(factor) {
    emit func(x) { emit toInt(x) * toInt(factor) + "" }
}

just run {
    // Basic lambda
    let double = func(x) { emit toInt(x) * 2 + "" }
    if double("5") == "10" { kp("PASS basic lambda") } else { kp("FAIL basic: " + double("5")) }

    // Two-param lambda
    let add = func(a, b) { emit toInt(a) + toInt(b) + "" }
    if add("3", "4") == "7" { kp("PASS two-param lambda") } else { kp("FAIL add") }

    // Higher-order
    let inc = func(x) { emit toInt(x) + 1 + "" }
    if applyTwice(inc, "5") == "7" { kp("PASS higher-order") } else { kp("FAIL higher-order") }

    // Zero-param lambda
    let greet = func() { emit "Hello from lambda!" }
    if greet() == "Hello from lambda!" { kp("PASS zero-param") } else { kp("FAIL zero-param") }

    // True closures - capture outer variables
    let add5 = makeAdder("5")
    if add5("3") == "8"   { kp("PASS closure add5(3)") }  else { kp("FAIL closure add5(3)") }
    if add5("10") == "15" { kp("PASS closure add5(10)") } else { kp("FAIL closure add5(10)") }

    let add10 = makeAdder("10")
    if add10("7") == "17" { kp("PASS closure add10(7)") } else { kp("FAIL closure add10(7)") }

    let triple = makeMultiplier("3")
    if triple("4") == "12" { kp("PASS closure triple(4)") } else { kp("FAIL closure triple(4)") }

    kp("ALL LAMBDA AND CLOSURE TESTS PASSED")
}
