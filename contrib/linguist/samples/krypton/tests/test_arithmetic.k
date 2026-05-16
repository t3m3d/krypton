// Test arithmetic operations
// Verifies +, -, *, /, % with various values

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Arithmetic Tests")
    kp("================")

    // Addition
    check("add positive", "5", "" + (2 + 3))
    check("add zero", "7", "" + (7 + 0))
    check("add large", "1000000", "" + (999999 + 1))

    // Subtraction
    check("sub positive", "3", "" + (5 - 2))
    check("sub zero", "5", "" + (5 - 0))
    check("sub negative result", "-3", "" + (2 - 5))

    // Multiplication
    check("mul basic", "12", "" + (3 * 4))
    check("mul zero", "0", "" + (5 * 0))
    check("mul one", "7", "" + (7 * 1))
    check("mul large", "10000", "" + (100 * 100))

    // Division
    check("div exact", "5", "" + (10 / 2))
    check("div truncate", "3", "" + (10 / 3))
    check("div one", "7", "" + (7 / 1))
    check("div self", "1", "" + (42 / 42))

    // Modulo
    check("mod basic", "1", "" + (10 % 3))
    check("mod even", "0", "" + (10 % 2))
    check("mod larger", "3", "" + (3 % 5))
    check("mod one", "0", "" + (7 % 1))

    // Mixed Operations
    check("add then mul", "14", "" + (2 + 3) * 2 + 4)
    check("complex", "7", "" + (1 + 2 * 3))

    emit "ok"
}
