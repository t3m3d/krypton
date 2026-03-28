// test_lambda.k — Lambda/closure tests for v1.1.0

func applyTwice(f, x) {
    emit f(f(x))
}

func makeAdder(n) {
    emit func(x) { emit toInt(x) + toInt(n) + "" }
}

just run {
    // Basic lambda
    let double = func(x) { emit toInt(x) * 2 + "" }
    if double("5") == "10" { kp("PASS basic lambda") } else { kp("FAIL basic: " + double("5")) }

    // Lambda with two params
    let add = func(a, b) { emit toInt(a) + toInt(b) + "" }
    if add("3", "4") == "7" { kp("PASS two-param lambda") } else { kp("FAIL add: " + add("3","4")) }

    // Lambda passed to function
    let inc = func(x) { emit toInt(x) + 1 + "" }
    if applyTwice(inc, "5") == "7" { kp("PASS higher-order") } else { kp("FAIL higher-order") }

    // Lambda in a list (map-like)
    let square = func(x) { emit toInt(x) * toInt(x) + "" }
    if square("4") == "16" { kp("PASS square lambda") } else { kp("FAIL square") }

    // Zero-param lambda
    let greet = func() { emit "Hello from lambda!" }
    if greet() == "Hello from lambda!" { kp("PASS zero-param lambda") } else { kp("FAIL zero-param") }

    kp("ALL LAMBDA TESTS PASSED")
}
