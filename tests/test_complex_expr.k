// Test complex expressions

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func abs(n) {
    if n < 0 { emit 0 - n }
    emit n
}

func max(a, b) {
    if a > b { emit a }
    emit b
}

func min(a, b) {
    if a < b { emit a }
    emit b
}

func clamp(v, lo, hi) {
    if v < lo { emit lo }
    if v > hi { emit hi }
    emit v
}

just run {
    kp("Complex Expression Tests")
    kp("========================")

    // Multi-operation expressions
    check("chain ops", "30", "" + ((2 + 3) * (4 + 2)))
    check("nested parens", "5", "" + ((10 + 10) / (2 + 2)))

    // Function composition
    check("abs positive", "5", "" + abs(5))
    check("abs negative", "5", "" + abs(0 - 5))
    check("max", "10", "" + max(5, 10))
    check("min", "5", "" + min(5, 10))
    check("clamp low", "0", "" + clamp(0 - 5, 0, 100))
    check("clamp high", "100", "" + clamp(150, 0, 100))
    check("clamp mid", "50", "" + clamp(50, 0, 100))

    // Complex string building
    let sb = sbNew()
    let i = 0
    while i < 5 {
        sb = sbAppend(sb, "" + (i * i))
        if i < 4 {
            sb = sbAppend(sb, ",")
        }
        i = i + 1
    }
    check("squares list", "0,1,4,9,16", sbToString(sb))

    // Chained comparisons
    let x = 5
    let inRange = x >= 1 && x <= 10
    if inRange {
        check("in range", "true", "true")
    } else {
        check("in range", "true", "false")
    }

    emit "ok"
}
