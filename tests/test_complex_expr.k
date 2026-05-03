// Test complex expressions

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

func m_abs(n) {
    if n < 0 { emit 0 - n }
    emit n
}

func m_max(a, b) {
    if a > b { emit a }
    emit b
}

func m_min(a, b) {
    if a < b { emit a }
    emit b
}

func m_clamp(v, lo, hi) {
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
    check("m_abs positive", "5", "" + m_abs(5))
    check("m_abs negative", "5", "" + m_abs(0 - 5))
    check("m_max", "10", "" + m_max(5, 10))
    check("m_min", "5", "" + m_min(5, 10))
    check("m_clamp low", "0", "" + m_clamp(0 - 5, 0, 100))
    check("m_clamp high", "100", "" + m_clamp(150, 0, 100))
    check("m_clamp mid", "50", "" + m_clamp(50, 0, 100))

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
